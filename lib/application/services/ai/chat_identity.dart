/// Explicit user preferences are facts, not something a language model should
/// reconstruct from its own older replies. No assistant-authored names count.
class ChatIdentity {
  static String? answer(String question, List<Map<String, dynamic>> history) {
    final q = question.toLowerCase();
    if (RegExp(
      r'\b(account|bank|merchant|category|goal|budget|payment|transaction|backup|file|receipt)\b',
    ).hasMatch(q)) {
      return null;
    }
    if (!RegExp(r'\bname\b|\bcall me\b').hasMatch(q) ||
        !RegExp(r'\bmy\b|\bme\b').hasMatch(q) ||
        RegExp(
          r'\b(first|previous|old|original|earlier|forget|remove)\b',
        ).hasMatch(q)) {
      return null;
    }
    String? current;
    int lastId = -1;
    for (final message in [
      ...history,
      {'text': question, 'isUser': true},
    ]) {
      if (message['isUser'] != true || message['failed'] == true) continue;
      final text = '${message['text']}'.trim();
      if (RegExp(
        r'\b(?:forget|remove) my name\b|don.t remember my name',
        caseSensitive: false,
      ).hasMatch(text)) {
        current = null;
        lastId = -1;
        continue;
      }
      final found = RegExp(
        r'^(?:(?:actually|please|instead|now)[, ]+)?(?:my name is|call me)\s+([A-Za-z][A-Za-z0-9 \x27-]{0,39})[.!]?$',
        caseSensitive: false,
      ).firstMatch(text);
      if (found == null ||
          RegExp(
            r'\b(and|but|then|because|ignore)\b',
            caseSensitive: false,
          ).hasMatch(found[1]!)) {
        continue;
      }
      final id = message['id'] as int?;
      if (id != null && id < lastId) continue;
      current = found[1]!.trim();
      if (id != null) lastId = id;
    }
    if (current == null) {
      return 'I don’t have a current name preference available. What would you like me to call you?';
    }
    return 'You asked me to call you $current.';
  }
}
