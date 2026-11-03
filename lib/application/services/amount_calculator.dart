/// Small, bounded arithmetic parser. Never executes code or calls an AI model.
/// Rational arithmetic avoids rounding each intermediate operation to paise.
abstract final class AmountCalculator {
  static String evaluate(String expression) {
    final text = expression
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAll('−', '-')
        .replaceAll(' ', '');
    if (text.isEmpty ||
        text.length > 120 ||
        !RegExp(
          r'^\d+(?:\.\d{0,2})?(?:[+*/-]\d+(?:\.\d{0,2})?)*$',
        ).hasMatch(text)) {
      throw const FormatException('Complete the calculation');
    }
    final tokens = RegExp(
      r'\d+(?:\.\d{0,2})?|[+*/-]',
    ).allMatches(text).map((m) => m.group(0)!).toList();
    _Fraction number(String token) {
      final parts = token.split('.');
      if (parts[0].length > 12) {
        throw const FormatException('Amount is too large');
      }
      final decimals = parts.length == 1 ? '' : parts[1];
      return _Fraction(
        BigInt.parse('${parts[0]}$decimals'),
        BigInt.from(10).pow(decimals.length),
      );
    }

    var sum = _Fraction(BigInt.zero, BigInt.one);
    var term = number(tokens.first);
    var sign = 1;
    for (var i = 1; i < tokens.length; i += 2) {
      final next = number(tokens[i + 1]);
      switch (tokens[i]) {
        case '*':
          term = term.multiply(next);
        case '/':
          if (next.n == BigInt.zero) {
            throw const FormatException('Cannot divide by zero');
          }
          term = term.divide(next);
        default:
          sum = sum.add(term.signed(sign));
          sign = tokens[i] == '+' ? 1 : -1;
          term = next;
      }
    }
    final result = sum.add(term.signed(sign));
    if (result.n <= BigInt.zero) {
      throw const FormatException('Amount must be greater than zero');
    }
    final scaled = result.n * BigInt.from(100);
    var paise = scaled ~/ result.d;
    if ((scaled % result.d) * BigInt.two >= result.d) paise += BigInt.one;
    if (paise == BigInt.zero) {
      throw const FormatException('Amount is less than ₹0.01');
    }
    if (paise > BigInt.parse('99999999999999')) {
      throw const FormatException('Amount is too large');
    }
    return '${paise ~/ BigInt.from(100)}.${(paise % BigInt.from(100)).toString().padLeft(2, '0')}';
  }
}

class _Fraction {
  final BigInt n, d;
  factory _Fraction(BigInt n, BigInt d) {
    final gcd = n.gcd(d);
    return _Fraction._(n ~/ gcd, d ~/ gcd);
  }
  const _Fraction._(this.n, this.d);
  _Fraction add(_Fraction b) => _Fraction(n * b.d + b.n * d, d * b.d);
  _Fraction multiply(_Fraction b) => _Fraction(n * b.n, d * b.d);
  _Fraction divide(_Fraction b) => _Fraction(n * b.d, d * b.n);
  _Fraction signed(int sign) => _Fraction(n * BigInt.from(sign), d);
}
