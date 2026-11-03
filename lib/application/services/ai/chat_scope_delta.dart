import 'chat_policy.dart';

/// Recognises a complete temporal edit, not an arbitrary topic containing a
/// month. The compiler supplies the new window; this only binds the edit to
/// the previous app-resolved query.
class ChatScopeDelta {
  static bool periodOnly(String question) {
    var q = ChatPolicy.normalizedQuestion(question);
    q = q.replaceFirst(
      RegExp(r'^(?:(?:please|and|what about|how about|instead|now|again)\s+)+'),
      '',
    );
    q = q.replaceFirst(
      RegExp(
        r'^(?:repeat|redo|run|do|show) (?:it|that|the same(?: query)?)(?: again)?\s*',
      ),
      '',
    );
    q = q.replaceFirst(RegExp(r'(?:\s+(?:instead|again|please|then))+$'), '');
    q = q.replaceFirst(RegExp(r'^(?:in|for|during)\s+'), '');
    return RegExp('^${ChatPolicy.periodPattern}\$').hasMatch(q);
  }
}
