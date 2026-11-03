import 'package:shared_preferences/shared_preferences.dart';

class BudgetUpdatePreferences {
  final bool morning, evening, limits, weekly;
  final int morningMinute, eveningMinute, weeklyMinute;
  const BudgetUpdatePreferences({
    this.weekly = false,
    this.weeklyMinute = 540,
    this.morning = false,
    this.evening = false,
    this.limits = true,
    this.morningMinute = 480,
    this.eveningMinute = 1260,
  });
  static Future<BudgetUpdatePreferences> load() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    int time(String key, int fallback) =>
        (p.getInt(key) ?? fallback).clamp(0, 1439);
    return BudgetUpdatePreferences(
      weekly: p.getBool('spending_weekly') ?? false,
      weeklyMinute: time('spending_weekly_time', 540),
      morning: p.getBool('budget_morning') ?? false,
      evening: p.getBool('budget_evening') ?? false,
      limits: p.getBool('budget_limits') ?? true,
      morningMinute: time('budget_morning_time', 480),
      eveningMinute: time('budget_evening_time', 1260),
    );
  }

  Future<void> save() async {
    if (weeklyMinute < 0 ||
        weeklyMinute > 1439 ||
        morningMinute < 0 ||
        eveningMinute > 1439 ||
        morningMinute >= eveningMinute) {
      throw ArgumentError('Morning time must be before evening time.');
    }
    final p = await SharedPreferences.getInstance();
    await p.setBool('spending_weekly', weekly);
    await p.setInt('spending_weekly_time', weeklyMinute);
    await p.setBool('budget_morning', morning);
    await p.setBool('budget_evening', evening);
    await p.setBool('budget_limits', limits);
    await p.setInt('budget_morning_time', morningMinute);
    await p.setInt('budget_evening_time', eveningMinute);
  }
}

/// Windows prevent an old morning update being delivered late at night.
bool budgetUpdateDue(
  DateTime now,
  int minute, {
  int? beforeMinute,
  Duration maxDelay = const Duration(hours: 2),
}) {
  final start = DateTime(
    now.year,
    now.month,
    now.day,
    minute ~/ 60,
    minute % 60,
  );
  final deadline = beforeMinute == null
      ? start.add(maxDelay)
      : DateTime(
          now.year,
          now.month,
          now.day,
          beforeMinute ~/ 60,
          beforeMinute % 60,
        );
  final end = start.add(maxDelay);
  return !now.isBefore(start) &&
      now.isBefore(deadline.isBefore(end) ? deadline : end);
}

class DailyBudgetFigures {
  final int allowance, today, remaining, periodOverspend;
  const DailyBudgetFigures(
    this.allowance,
    this.today,
    this.remaining,
    this.periodOverspend,
  );
  factory DailyBudgetFigures.calculate({
    required int limit,
    required int spentBeforeToday,
    required int spentToday,
    required DateTime today,
    required DateTime end,
  }) {
    final days = DateTime.utc(
      end.year,
      end.month,
      end.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
    final before = limit - spentBeforeToday;
    final allowance = days > 0 && before > 0 ? before ~/ days : 0;
    final remaining = limit - spentBeforeToday - spentToday;
    return DailyBudgetFigures(
      allowance,
      spentToday,
      remaining,
      remaining < 0 ? -remaining : 0,
    );
  }
  int get availableToday => (allowance - today).clamp(0, allowance);
  int get dailyDifference => allowance - today;
}
