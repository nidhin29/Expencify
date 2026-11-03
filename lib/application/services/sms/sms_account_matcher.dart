import '../../../domain/entities/account.dart';

String _bank(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
const _aliases = <String, List<String>>{
  'bankofbaroda': ['bob', 'baroda'],
  'statebankofindia': ['sbi'],
  'hdfcbank': ['hdfc'],
  'icicibank': ['icici'],
  'axisbank': ['axis'],
  'punjabnationalbank': ['pnb'],
  'canarabank': ['canara'],
  'unionbankofindia': ['unionbank'],
  'kotakmahindrabank': ['kotak'],
  'federalbank': ['federal'],
  'southindianbank': ['sib'],
};
bool bankMatches(Account account, String body, String? sender) {
  final bank = _bank(account.bankName);
  if (bank.isEmpty || bank == 'cash') return false;
  final names = {bank, ...?_aliases[bank]};
  final text = _bank(body);
  final senderWords = (sender ?? '').toLowerCase().split(RegExp(r'[^a-z0-9]+'));
  return names.any(
    (n) =>
        n.length >= 3 &&
        (text.contains(n) || senderWords.any((s) => s == n || s == '${n}bk')),
  );
}

/// Sender/name hints disambiguate accounts; they do not authenticate an SMS.
Account? matchSmsAccount(
  List<Account> accounts,
  String digits,
  String body,
  String? sender,
) {
  final banks = accounts
      .where(
        (a) =>
            _bank(a.bankName) != 'cash' &&
            a.accountNumber.toUpperCase() != 'CASH',
      )
      .toList();
  if (digits.isNotEmpty) {
    final candidates = banks
        .where((a) => a.accountNumber.endsWith(digits))
        .toList();
    if (candidates.length == 1) return candidates.single;
    final hinted = candidates
        .where((a) => bankMatches(a, body, sender))
        .toList();
    return hinted.length == 1 ? hinted.single : null;
  }
  final hinted = banks.where((a) => bankMatches(a, body, sender)).toList();
  return hinted.length == 1 ? hinted.single : null;
}
