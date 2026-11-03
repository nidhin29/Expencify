/// Calendar boundaries shared by manual and SMS budget checks.
(DateTime, DateTime) budgetPeriod(String period, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  switch (period) {
    case 'weekly':
      final start = today.subtract(Duration(days: today.weekday - 1));
      return (start, start.add(const Duration(days: 7)));
    case 'yearly':
      return (DateTime(now.year), DateTime(now.year + 1));
    default:
      return (DateTime(now.year, now.month), DateTime(now.year, now.month + 1));
  }
}
