import 'dart:convert';
import '../ai/chat_policy.dart';
import '../ai/chat_plan_constraints.dart';
import '../ai/chat_scope.dart';

/// Bounded extractive notes, exclusively from the user's own words. No generated
/// summary, assistant amounts or inferred personal facts are persisted here.
class ChatMemory {
  static List<Map<String, dynamic>> decode(String raw) {
    try {
      final list = jsonDecode(raw);
      if (list is! List || raw.length > 4000) return [];
      return list
          .whereType<Map>()
          .where(
            (m) => m['id'] is int && m['key'] is String && m['text'] is String,
          )
          .map((m) => Map<String, dynamic>.from(m))
          .take(4)
          .toList();
    } on FormatException {
      return [];
    }
  }

  static String update(String raw, String text, int id) {
    if (ChatPolicy.unsafeOrAdviceReply(text) != null) return raw;
    final notes = decode(raw)..removeWhere((n) => n['id'] == id);
    final q = ChatPolicy.normalizedQuestion(text);
    String? key;
    if (RegExp(
      r'\b(?:forget|remove) my name\b|\bdon t remember my name\b',
    ).hasMatch(q)) {
      notes.removeWhere((n) => n['key'] == 'identity');
    } else if (RegExp(
      r'^(?:(?:actually|please|instead|now) )?(?:my name is|call me)\b',
    ).hasMatch(q)) {
      key = 'identity';
    } else if (RegExp(r'^(?:i prefer|please use|my preferred)\b').hasMatch(q)) {
      key = 'preference';
    } else if (ChatPlanConstraints.recordRequest(text) ||
        ChatScope.appHelp(text)) {
      key = 'topic';
    }
    if (key != null && text.length <= 180) {
      if (key == 'topic') {
        final topics = notes.where((n) => n['key'] == 'topic').toList();
        if (topics.length >= 2) notes.remove(topics.first);
      } else {
        notes.removeWhere((n) => n['key'] == key);
      }
      notes.add({'key': key, 'id': id, 'text': text});
    }
    notes.sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
    return jsonEncode(notes);
  }

  static List<Map<String, dynamic>> history(String raw, {int? beforeId}) =>
      decode(raw)
          .where((n) => beforeId == null || (n['id'] as int) < beforeId)
          .map(
            (n) => {
              'text': n['text'],
              'id': n['id'],
              'isUser': true,
              'memory': true,
            },
          )
          .toList();
}
