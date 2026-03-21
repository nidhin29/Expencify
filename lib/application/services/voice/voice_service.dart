import 'dart:developer';

import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceService {
  final SpeechToText _speechToText = SpeechToText();

  Future<bool> initSpeech() async {
    try {
      // Explicitly check for microphone permission first to avoid plugin-level crashes
      var status = await Permission.microphone.status;
      if (status.isDenied) {
        status = await Permission.microphone.request();
        if (!status.isGranted) return false;
      }

      return await _speechToText.initialize(
        onError: (error) => log('Speech Error: $error'),
        onStatus: (status) => log('Speech Status: $status'),
      );
    } catch (e) {
      log('Speech Init Error: $e');
      return false;
    }
  }

  Future<bool> startListening(Function(String) onResult) async {
    try {
      if (!_speechToText.isAvailable) {
        bool ok = await initSpeech();
        if (!ok) return false;
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
      return true;
    } catch (e) {
      log('Speech Listen Error: $e');
      return false;
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
