import 'ai_guardrails.dart';

class VoiceAmountRole {
  final String role, label;
  const VoiceAmountRole(this.role, this.label);
}

/// A deliberately bounded grammar for amount-before-item speech. It recognises
/// explicit breakdown markers and verifies their arithmetic before asking the
/// model for categories. Unsupported phrasing is left for strict AI review.
class VoiceSplitStructure {
  static final _breakdown = RegExp(
    r'\b(?:total|overall|altogether|of which|in that|including|split|breakdown|divided into|consisting of)\b',
    caseSensitive: false,
  );
  static bool declaresBreakdown(String source) => _breakdown.hasMatch(source);
  static List<VoiceAmountRole>? parse(
    String source,
    List<({int start, int end, double value})> mentions,
  ) {
    if (mentions.length < 2 || mentions.length > 8) return null;
    if (mentions.any(
      (m) =>
          m.value <= 0 ||
          !m.value.isFinite ||
          m.value > 1e12 ||
          (m.value * 100 - (m.value * 100).round()).abs() > .0001,
    )) {
      return null;
    }
    final values = mentions.map((m) => (m.value * 100).round()).toList();
    final sum = values.fold<int>(0, (n, v) => n + v);
    final whole = [
      for (var i = 0; i < values.length; i++)
        if (values[i] * 2 == sum) i,
    ];
    int? total;
    if (_breakdown.hasMatch(source)) {
      if (mentions.length < 3 || whole.length != 1) return null;
      total = whole.single;
    } else if (mentions.length >= 3 && whole.isNotEmpty) {
      return null; // Could be a total or coincidentally equal separate expenses.
    }
    final roles = <VoiceAmountRole>[];
    for (var i = 0; i < mentions.length; i++) {
      if (i == total) {
        roles.add(const VoiceAmountRole('total', ''));
        continue;
      }
      var tail = source
          .substring(
            mentions[i].end,
            i + 1 == mentions.length ? source.length : mentions[i + 1].start,
          )
          .trim();
      final lead = RegExp(
        r'^(?:(?:rupees?|rs\.?|inr)\s+)?(?:(?:was|were|is|are|went)\s+)?(?:for|on|towards)\s+',
        caseSensitive: false,
      ).firstMatch(tail);
      if (lead == null) return null;
      tail = tail.substring(lead.end).trim();
      tail = tail
          .replaceFirst(
            RegExp(
              r'[\s,;:]*(?:(?:and|plus|then|also|total|overall|altogether)[\s,;:]*)+$',
              caseSensitive: false,
            ),
            '',
          )
          .trim();
      tail = tail.replaceFirst(RegExp(r'[.!?,;:]+$'), '').trim();
      if (tail.isEmpty ||
          tail.length > 80 ||
          AiGuardrails.numbers(tail).isNotEmpty) {
        return null;
      }
      roles.add(VoiceAmountRole('part', tail));
    }
    return roles;
  }
}
