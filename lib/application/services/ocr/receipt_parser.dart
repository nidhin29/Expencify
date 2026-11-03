/// Deterministic receipt draft: only confidently labelled totals are selected.
/// A list of prices alone is not enough evidence to choose the largest one.
class ReceiptParser {
  static Map<String, dynamic> parse(String text) {
    final lines = text.split(RegExp(r'[\r\n]+'));
    final totals = <(int, double)>[];
    final amounts = <double>{};
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      for (final match in RegExp(
        r'(?:₹|INR|Rs\.?)\s*([\d,]+(?:\.\d{1,2})?)|\b(\d[\d,]*\.\d{2})\b',
        caseSensitive: false,
      ).allMatches(line)) {
        final value = double.tryParse(
          (match.group(1) ?? match.group(2)!).replaceAll(',', ''),
        );
        if (value != null && value.isFinite && value > 0) amounts.add(value);
      }
      if (RegExp(
        r'\b(sub\s*total|subtotal|total\s*(?:items?|qty|quantity|discount|savings))\b',
        caseSensitive: false,
      ).hasMatch(line)) {
        continue;
      }
      final label = RegExp(
        r'\b(grand\s*total|net\s*(?:total|amount|payable)|amount\s*(?:due|payable)|total\s*payable|total)\b',
        caseSensitive: false,
      ).firstMatch(line);
      if (label == null) continue;
      var tail = line
          .substring(label.end)
          .replaceFirst(RegExp(r'^\s*[:=]\s*'), '')
          .trim();
      if (tail.isEmpty && i + 1 < lines.length) tail = lines[i + 1].trim();
      if (RegExp(r'^\s*[-(]').hasMatch(tail)) continue;
      final valueMatch = RegExp(
        r'^(?:₹|INR|Rs\.?)?\s*([\d,]+(?:\.\d{1,2})?)(?:\s|$)',
        caseSensitive: false,
      ).firstMatch(tail);
      if (valueMatch == null) continue;
      final value = double.tryParse(valueMatch.group(1)!.replaceAll(',', ''));
      if (value == null || !value.isFinite || value <= 0) continue;
      amounts.add(value);
      final labelText = label.group(0)!.toLowerCase();
      totals.add((
        labelText.startsWith('grand')
            ? 3
            : labelText == 'total'
            ? 1
            : 2,
        value,
      ));
    }
    totals.sort((a, b) => b.$1.compareTo(a.$1));
    final candidates = totals.isEmpty
        ? <double>{}
        : totals.where((t) => t.$1 == totals.first.$1).map((t) => t.$2).toSet();
    return {
      'text': text,
      'amount': candidates.length == 1 ? candidates.single : null,
      'amounts': amounts.toList(),
      'ambiguous': candidates.length > 1,
    };
  }
}
