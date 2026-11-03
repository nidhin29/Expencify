import 'dart:developer';

import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'voice_capture.dart';

class VoiceService implements VoiceCapture {
  final SpeechToText _speechToText = SpeechToText();
  int _session = 0;
  Future<void>? _pendingCancel;

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

  @override
  Future<bool> startListening(
    void Function(String) onResult, {
    void Function(String)? onPartial,
    void Function(String)? onError,
    void Function()? onStopped,
  }) async {
    final session = ++_session;
    try {
      await _pendingCancel;
      if (session != _session) return false;
      if (!_speechToText.isAvailable) {
        bool ok = await initSpeech();
        if (!ok) return false;
      }
      if (session != _session) return false;
      // SpeechToText is a singleton. Rebind listeners for each capture even
      // after it has already been initialized by an earlier Home instance.
      _speechToText.errorListener = (error) {
        if (session != _session) return;
        final message = switch (error.errorMsg) {
          'error_no_match' || 'error_speech_timeout' =>
            'No speech detected. Try again or enter the expense manually.',
          'error_permission' || 'error_insufficient_permissions' =>
            'Microphone access is off. Enable it in device settings and try again.',
          'error_network' || 'error_network_timeout' =>
            'Speech recognition is unavailable. Try again or enter the expense manually.',
          _ => 'Listening stopped unexpectedly. Please try again.',
        };
        onError?.call(message);
      };
      _speechToText.statusListener = (status) {
        if (session == _session &&
            (status == 'done' || status == 'notListening')) {
          onStopped?.call();
        }
      };
      await _speechToText.listen(
        onResult: (result) {
          if (session != _session) return;
          if (result.finalResult) {
            onResult(result.recognizedWords);
          } else {
            onPartial?.call(result.recognizedWords);
          }
        },
        listenFor: const Duration(minutes: 1),
        pauseFor: const Duration(seconds: 5),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
      );
      return true;
    } catch (e) {
      log('Speech Listen Error: $e');
      return false;
    }
  }

  @override
  Future<void> stopListening() async {
    try {
      await _speechToText.stop();
    } catch (e) {
      log('Speech Stop Error: $e');
    }
  }

  @override
  Future<void> cancelListening() {
    ++_session;
    final previous = _pendingCancel;
    final cancellation = () async {
      await previous;
      try {
        await _speechToText.cancel();
      } catch (e) {
        log('Speech Cancel Error: ${e.runtimeType}');
      }
    }();
    _pendingCancel = cancellation;
    return cancellation;
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
