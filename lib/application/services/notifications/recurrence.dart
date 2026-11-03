/// Calendar recurrence keeps the original day (31 Jan -> 28 Feb -> 31 Mar).
DateTime occurrence(DateTime anchor, String frequency, int step) {
  if (frequency == 'daily' || frequency == 'weekly') {
    return DateTime(
      anchor.year,
      anchor.month,
      anchor.day + step * (frequency == 'weekly' ? 7 : 1),
      anchor.hour,
      anchor.minute,
      anchor.second,
    );
  }
  final month = DateTime(
    anchor.year + (frequency == 'yearly' ? step : 0),
    anchor.month + (frequency == 'yearly' ? 0 : step),
  );
  final lastDay = DateTime(month.year, month.month + 1, 0).day;
  return DateTime(
    month.year,
    month.month,
    anchor.day > lastDay ? lastDay : anchor.day,
    anchor.hour,
    anchor.minute,
    anchor.second,
  );
}

Iterable<DateTime> upcomingOccurrences(
  DateTime anchor,
  String? frequency,
  DateTime now, {
  int count = 24,
}) sync* {
  if (frequency == null || frequency == 'once') {
    if (anchor.isAfter(now)) yield anchor;
    return;
  }
  if (!['daily', 'weekly', 'monthly', 'yearly'].contains(frequency)) {
    throw ArgumentError('Unsupported recurrence.');
  }
  var step = 0;
  if (frequency == 'monthly') {
    step = ((now.year - anchor.year) * 12 + now.month - anchor.month).clamp(
      0,
      100000,
    );
  }
  if (frequency == 'yearly') step = (now.year - anchor.year).clamp(0, 100000);
  if (frequency == 'daily' || frequency == 'weekly') {
    step = (now.difference(anchor).inDays ~/ (frequency == 'weekly' ? 7 : 1))
        .clamp(0, 10000000);
  }
  while (!occurrence(anchor, frequency, step).isAfter(now)) {
    step++;
  }
  for (var i = 0; i < count; i++) {
    yield occurrence(anchor, frequency, step + i);
  }
}
