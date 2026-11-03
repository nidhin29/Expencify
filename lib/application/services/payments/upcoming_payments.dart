import '../../../domain/entities/reminder.dart';
import '../../../domain/entities/subscription.dart';
import '../notifications/recurrence.dart';

class UpcomingPayment {
  final int? id;
  final String name, kind;
  final int cents;
  final DateTime due;
  const UpcomingPayment(this.id, this.name, this.kind, this.cents, this.due);
  bool overdue(DateTime now) =>
      due.isBefore(DateTime(now.year, now.month, now.day));
}

List<UpcomingPayment> upcomingPayments(
  List<Reminder> reminders,
  List<SubscriptionModel> subscriptions,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final end = DateTime(today.year, today.month, today.day + 7);
  final rows = <UpcomingPayment>[];
  void add(
    int? id,
    String name,
    String kind,
    double amount,
    DateTime due,
    String? frequency,
    DateTime anchor,
  ) {
    if (!amount.isFinite || amount < 0 || !due.isBefore(end)) return;
    rows.add(UpcomingPayment(id, name, kind, (amount * 100).round(), due));
    // An overdue item remains due until explicitly handled; do not invent paid cycles.
    if (due.isBefore(today) ||
        frequency == null ||
        !['daily', 'weekly', 'monthly', 'yearly'].contains(frequency)) {
      return;
    }
    for (final date in upcomingOccurrences(anchor, frequency, due, count: 8)) {
      if (!date.isBefore(end)) break;
      rows.add(UpcomingPayment(id, name, kind, (amount * 100).round(), date));
    }
  }

  for (final r in reminders) {
    add(
      r.id,
      r.title,
      'Reminder',
      r.amount,
      r.dueDate,
      r.isRecurring ? r.frequency : null,
      r.recurrenceAnchor ?? r.dueDate,
    );
  }
  for (final s in subscriptions.where((s) => s.isActive)) {
    add(
      s.id,
      s.name,
      'Subscription',
      s.amount,
      s.nextDueDate,
      s.frequency,
      s.nextDueDate,
    );
  }
  rows.sort((a, b) {
    final d = a.due.compareTo(b.due);
    return d == 0 ? a.name.compareTo(b.name) : d;
  });
  return rows;
}
