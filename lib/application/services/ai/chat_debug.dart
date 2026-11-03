import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Temporary console diagnostics for reproducing conversation failures.
/// Disabled in profile/release; never stored in analytics or app diagnostics.
class ChatDebug {
  ChatDebug({this.observe});
  final void Function(Map<String, Object?>)? observe;
  static int _nextId = 0;
  final int id = ++_nextId;

  void log(String event, [Map<String, Object?> fields = const {}]) {
    observe?.call({'id': id, 'event': event, ...fields});
    if (!kDebugMode) return;
    debugPrint(
      '[SpendyChat] ${jsonEncode({'id': id, 'event': event, ...fields})}',
    );
  }

  void raw(String stage, String text) {
    if (!kDebugMode) return;
    log('model_output', {
      'stage': stage,
      'chars': text.length,
      'truncated': text.length > 1000,
      'raw': text.length > 1000 ? text.substring(0, 1000) : text,
    });
  }

  void error(String stage, Object error) {
    if (!kDebugMode) return;
    final message = error.toString();
    log('generation_error', {
      'stage': stage,
      'type': error.runtimeType.toString(),
      'message': message.length > 500 ? message.substring(0, 500) : message,
    });
  }
}
