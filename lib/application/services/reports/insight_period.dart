import 'package:intl/intl.dart';

enum InsightPeriod { thisMonth, lastMonth, thisYear, allTime, custom }

extension InsightPeriodLabel on InsightPeriod {
  String get label => switch (this) {
    InsightPeriod.thisMonth => 'This month',
    InsightPeriod.lastMonth => 'Last month',
    InsightPeriod.thisYear => 'This year',
    InsightPeriod.allTime => 'All time',
    InsightPeriod.custom => 'Custom dates',
  };
}

class InsightWindow {
  final DateTime? from, to, previousFrom, previousTo;
  const InsightWindow(this.from, this.to, this.previousFrom, this.previousTo);
  bool get hasComparison => previousFrom != null && previousTo != null;
  static DateTime _end(DateTime date) => DateTime(
    date.year,
    date.month,
    date.day + 1,
  ).subtract(const Duration(microseconds: 1));
  static DateTime _equivalent(DateTime now, int year, int month) {
    final first = DateTime(year, month);
    final lastDay = DateTime(first.year, first.month + 1, 0).day;
    return DateTime(
      first.year,
      first.month,
      now.day > lastDay ? lastDay : now.day,
      now.hour,
      now.minute,
      now.second,
      now.millisecond,
      now.microsecond,
    );
  }

  factory InsightWindow.build(
    InsightPeriod period,
    DateTime now, {
    DateTime? customFrom,
    DateTime? customTo,
  }) {
    switch (period) {
      case InsightPeriod.thisMonth:
        return InsightWindow(
          DateTime(now.year, now.month),
          now,
          DateTime(now.year, now.month - 1),
          _equivalent(now, now.year, now.month - 1),
        );
      case InsightPeriod.lastMonth:
        return InsightWindow(
          DateTime(now.year, now.month - 1),
          DateTime(
            now.year,
            now.month,
          ).subtract(const Duration(microseconds: 1)),
          DateTime(now.year, now.month - 2),
          DateTime(
            now.year,
            now.month - 1,
          ).subtract(const Duration(microseconds: 1)),
        );
      case InsightPeriod.thisYear:
        return InsightWindow(
          DateTime(now.year),
          now,
          DateTime(now.year - 1),
          _equivalent(now, now.year - 1, now.month),
        );
      case InsightPeriod.allTime:
        return const InsightWindow(null, null, null, null);
      case InsightPeriod.custom:
        if (customFrom == null ||
            customTo == null ||
            customFrom.isAfter(customTo)) {
          throw ArgumentError('Invalid custom period');
        }
        final from = DateTime(
          customFrom.year,
          customFrom.month,
          customFrom.day,
        );
        final endDay = DateTime(customTo.year, customTo.month, customTo.day);
        final days =
            DateTime.utc(
              endDay.year,
              endDay.month,
              endDay.day,
            ).difference(DateTime.utc(from.year, from.month, from.day)).inDays +
            1;
        return InsightWindow(
          from,
          _end(endDay),
          DateTime(from.year, from.month, from.day - days),
          from.subtract(const Duration(microseconds: 1)),
        );
    }
  }
}

String insightRangeLabel(DateTime? from, DateTime? to) {
  if (from == null && to == null) return 'All time';
  if (to == null) return 'Since ${DateFormat('d MMM y').format(from!)}';
  if (from == null) return 'Through ${DateFormat('d MMM y').format(to)}';
  if (from.year == to.year && from.month == to.month) {
    if (from.day == to.day) return DateFormat('d MMM y').format(from);
    return '${from.day}–${DateFormat('d MMM y').format(to)}';
  }
  if (from.year == to.year) {
    return '${DateFormat('d MMM').format(from)} – ${DateFormat('d MMM y').format(to)}';
  }
  return '${DateFormat('d MMM y').format(from)} – ${DateFormat('d MMM y').format(to)}';
}

List<MapEntry<String, double>> insightEntries(Map<String, double> totals) =>
    totals.entries
        .where((e) => e.value.isFinite && e.value > 0)
        .map((e) => MapEntry(e.key, (e.value * 100).round() / 100))
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) {
        final amount = b.value.compareTo(a.value);
        return amount == 0 ? a.key.compareTo(b.key) : amount;
      });
double insightTotal(Iterable<MapEntry<String, double>> entries) =>
    entries.fold<int>(0, (s, e) => s + (e.value * 100).round()) / 100;

/// Every positive category is represented: small categories are aggregated, not hidden.
List<MapEntry<String, double>> insightSlices(
  List<MapEntry<String, double>> entries, {
  int visible = 5,
}) {
  if (entries.length <= visible) return [...entries];
  return [
    ...entries.take(visible),
    MapEntry('Other categories', insightTotal(entries.skip(visible))),
  ];
}
