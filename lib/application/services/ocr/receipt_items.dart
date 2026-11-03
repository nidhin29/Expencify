/// OCR geometry is retained so quantity and unit-price columns are never
/// used in place of an item's final amount.
class ReceiptWord {
  final String text;
  final double left, top, right, bottom;
  const ReceiptWord(this.text, this.left, this.top, this.right, this.bottom);
  double get x => (left + right) / 2;
  double get y => (top + bottom) / 2;
  double get height => bottom - top;
}

class ReceiptItem {
  final String name;
  final double? amount;
  const ReceiptItem(this.name, this.amount);
}

class ReceiptItems {
  static double? money(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'^(?:₹|Rs\.?|INR)\s*', caseSensitive: false), '')
        .replaceAll(',', '');
    if (!RegExp(r'^\d+(?:\.\d{2})?$').hasMatch(cleaned)) return null;
    final amount = double.tryParse(cleaned);
    return amount != null && amount.isFinite && amount > 0 ? amount : null;
  }

  static List<ReceiptItem> parse(List<ReceiptWord> words) {
    final ordered = [...words]..sort((a, b) => a.top.compareTo(b.top));
    final totalHeaders = ordered.where(
      (w) => RegExp(
        r'^(?:total|tot|amount|amt)\.?$',
        caseSensitive: false,
      ).hasMatch(w.text),
    );
    for (final total in totalHeaders) {
      final header = ordered
          .where((w) => (w.y - total.y).abs() <= (w.height + total.height) * .7)
          .toList();
      final quantities = header
          .where(
            (w) =>
                RegExp(
                  r'^(?:qty|quantity)$',
                  caseSensitive: false,
                ).hasMatch(w.text) &&
                w.x < total.x,
          )
          .toList();
      final names = header
          .where(
            (w) => RegExp(
              r'item|description|particular|product',
              caseSensitive: false,
            ).hasMatch(w.text),
          )
          .toList();
      final prices = header
          .where(
            (w) =>
                RegExp(
                  r'^(?:mrp|rate|price)$',
                  caseSensitive: false,
                ).hasMatch(w.text) &&
                w.x < total.x,
          )
          .toList();
      if (names.isEmpty || names.first.x >= total.x) continue;
      final numericHeaders = [...quantities, ...prices]
        ..sort((a, b) => a.left.compareTo(b.left));
      final nameRight = numericHeaders.isEmpty
          ? total.left
          : numericHeaders.first.left;
      final footer = ordered
          .where(
            (w) =>
                w.top > total.bottom &&
                RegExp(
                  r'^(?:tax%?|taxable|cgst|sgst|subtotal|sub-total|saved|savings|round|grand|total)\b',
                  caseSensitive: false,
                ).hasMatch(w.text),
          )
          .toList();
      final end = footer.isEmpty ? double.infinity : footer.first.top;
      final result = <ReceiptItem>[];
      // Anchor to the total header even if OCR misreads another header.
      final candidates = ordered
          .where(
            (w) =>
                w.top > total.bottom &&
                w.top < end &&
                w.right >= total.left &&
                w.x >= total.left - total.height * .8,
          )
          .toList();
      final nameWords = ordered
          .where(
            (w) =>
                w.top > total.bottom &&
                w.top < end &&
                w.left >= names.first.left - names.first.height &&
                w.right < nameRight,
          )
          .toList();
      final rows = <List<ReceiptWord>>[];
      for (final word in nameWords) {
        final row = rows
            .where(
              (r) =>
                  (r.first.y - word.y).abs() <=
                  (r.first.height + word.height) * .6,
            )
            .firstOrNull;
        if (row == null) {
          rows.add([word]);
        } else {
          row.add(word);
        }
      }
      for (final row in rows) {
        row.sort((a, b) => a.left.compareTo(b.left));
        final amounts = candidates
            .where(
              (w) =>
                  (w.y - row.first.y).abs() <=
                  (w.height + row.first.height) * .6,
            )
            .map((w) => money(w.text))
            .whereType<double>()
            .toList();
        final name = row
            .map((w) => w.text)
            .join(' ')
            .replaceFirst(RegExp(r'^\d+\s+'), '')
            .trim();
        if (name.isEmpty || !RegExp(r'[a-zA-Z\u0080-\uFFFF]').hasMatch(name)) {
          continue;
        }
        result.add(
          ReceiptItem(name, amounts.length == 1 ? amounts.single : null),
        );
      }
      if (result.isNotEmpty) return result;
    }
    return const [];
  }
}
