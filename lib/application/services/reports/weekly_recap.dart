import '../../../domain/repositories/transaction_repository.dart';
import 'insight_period.dart';

class WeeklyRecap {
  final DateTime from, to, previousFrom;
  final List<MapEntry<String, double>> current, previous;
  const WeeklyRecap(
    this.from,
    this.to,
    this.previousFrom,
    this.current,
    this.previous,
  );
  int get total => (insightTotal(current) * 100).round();
  int get priorTotal => (insightTotal(previous) * 100).round();
  int get difference => total - priorTotal;
  List<MapEntry<String, int>> get changes {
    final a = {for (final e in current) e.key: (e.value * 100).round()};
    final b = {for (final e in previous) e.key: (e.value * 100).round()};
    final rows = {
      ...a.keys,
      ...b.keys,
    }.map((k) => MapEntry(k, (a[k] ?? 0) - (b[k] ?? 0))).toList();
    rows.sort((a, b) {
      final d = b.value.abs().compareTo(a.value.abs());
      return d == 0 ? a.key.compareTo(b.key) : d;
    });
    return rows;
  }

  static Future<WeeklyRecap> load(
    TransactionRepository repo,
    DateTime now, {
    int? accountId,
  }) async {
    final day = DateTime(now.year, now.month, now.day);
    final end = DateTime(day.year, day.month, day.day - day.weekday + 1);
    final from = DateTime(end.year, end.month, end.day - 7);
    final previous = DateTime(end.year, end.month, end.day - 14);
    final data = await Future.wait([
      repo.getCategoryTotals(
        type: 'expense',
        from: from,
        to: end.subtract(const Duration(microseconds: 1)),
        accountId: accountId,
      ),
      repo.getCategoryTotals(
        type: 'expense',
        from: previous,
        to: from.subtract(const Duration(microseconds: 1)),
        accountId: accountId,
      ),
    ]);
    return WeeklyRecap(
      from,
      end.subtract(const Duration(microseconds: 1)),
      previous,
      insightEntries(data[0]),
      insightEntries(data[1]),
    );
  }
}
