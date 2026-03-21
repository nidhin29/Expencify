import 'dart:developer';

import 'package:speech_to_text/speech_to_text.dart';

class VoiceService {
  final SpeechToText _speechToText = SpeechToText();

  Future<bool> initSpeech() async {
    try {
      return await _speechToText.initialize();
    } catch (e) {
      log('Speech Init Error: $e');
      return false;
    }
  }

  Future<void> startListening(Function(String) onResult) async {
    try {
      if (!_speechToText.isAvailable) {
        bool ok = await initSpeech();
        if (!ok) return;
      }
      await _speechToText.listen(
        onResult: (result) {
          if (result.finalResult) {
            onResult(result.recognizedWords);
          }
        },
        listenFor: const Duration(
          minutes: 5,
        ), // Allow up to 5 minutes of continuous recording
        pauseFor: const Duration(
          seconds: 15,
        ), // Wait 15 seconds of absolute silence before auto-stopping
      );
    } catch (e) {
      log('Speech Listen Error: $e');
    }
  }

  Future<void> stopListening() async {
    try {
      await _speechToText.stop();
    } catch (e) {
      log('Speech Stop Error: $e');
    }
  }

  // Simple parser to find keywords like "spent", "income", "amount"
  Map<String, dynamic>? parseVoiceCommand(String text) {
    try {
      text = text.toLowerCase();

      RegExp amountRegExp = RegExp(r'(\d+)');
      var match = amountRegExp.firstMatch(text);

      double? amount;
      if (match != null) {
        amount = double.tryParse(match.group(0)!);
      }

      String type = 'expense';
      if (text.contains('income') ||
          text.contains('earned') ||
          text.contains('received')) {
        type = 'income';
      }

      if (amount != null) {
        return {'amount': amount, 'type': type, 'raw_text': text};
      }
    } catch (e) {
      log('Voice Parse Error: $e');
    }
    return null;
  }
}
