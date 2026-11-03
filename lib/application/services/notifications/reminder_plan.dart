import 'recurrence.dart';

enum ReminderKind {
  payment(100000000, 400000000, 'reminders', 1),
  appliance(200000000, 500000000, 'appliances', 7),
  subscription(300000000, 600000000, 'subscriptions', 2);

  final int legacyNamespace, namespace, leadDays;
  final String channel;
  const ReminderKind(
    this.legacyNamespace,
    this.namespace,
    this.channel,
    this.leadDays,
  );
}

class PlannedReminder {
  final int id;
  final DateTime at;
  final String channel, title, body;
  const PlannedReminder(this.id, this.at, this.channel, this.title, this.body);
}

class ReminderRecord {
  final ReminderKind kind;
  final int id;
  final String name, brand;
  final double amount;
  final DateTime due;
  final DateTime? anchor;
  final String? frequency;
  const ReminderRecord({
    required this.kind,
    required this.id,
    required this.name,
    required this.due,
    this.anchor,
    this.amount = 0,
    this.brand = '',
    this.frequency,
  });
  String get key => '${kind.channel}:$id';
  bool sameSchedule(ReminderRecord other) =>
      key == other.key &&
      name == other.name &&
      brand == other.brand &&
      amount == other.amount &&
      due == other.due &&
      (frequency == null ||
          frequency == 'once' ||
          (anchor ?? due) == (other.anchor ?? other.due)) &&
      frequency == other.frequency;
}

/// Calendar-only plan. IDs belong to an occurrence, not its position in today's
/// queue, so background renewal cannot replay alerts that have already fired.
class ReminderPlan {
  static const stride = 64, occurrences = 24;
  static DateTime alertTime(DateTime date) =>
      date.hour == 0 &&
          date.minute == 0 &&
          date.second == 0 &&
          date.millisecond == 0
      ? DateTime(date.year, date.month, date.day, 9)
      : date;

  static bool managed(int id) => ReminderKind.values.any(
    (k) =>
        id >= k.legacyNamespace && id < k.legacyNamespace + 100000000 ||
        id >= k.namespace && id < k.namespace + 100000000,
  );

  static Iterable<int> cancellationIds(ReminderKind kind, int id) sync* {
    _validateId(id);
    for (var i = 0; i < occurrences; i++) {
      yield kind.legacyNamespace + id * 32 + i;
    }
    for (var i = 0; i < occurrences * 2; i++) {
      yield kind.namespace + id * stride + i;
    }
  }

  static void _validateId(int id) {
    if (id <= 0 || id * stride + occurrences * 2 >= 100000000) {
      throw ArgumentError('Reminder ID is outside its notification range');
    }
  }

  static List<PlannedReminder> forRecord(
    ReminderRecord record,
    DateTime now, {
    bool catchUp = false,
  }) {
    _validateId(record.id);
    final recurring = record.frequency != null && record.frequency != 'once';
    final anchor = alertTime(
      recurring ? record.anchor ?? record.due : record.due,
    );
    final first = alertTime(record.due);
    final lower = first.isAfter(now)
        ? first.subtract(const Duration(microseconds: 1))
        : now;
    final result = <PlannedReminder>[];
    for (final due in upcomingOccurrences(
      anchor,
      record.frequency,
      lower,
      count: occurrences,
    )) {
      final step = switch (record.frequency) {
        'daily' =>
          DateTime.utc(due.year, due.month, due.day)
              .difference(DateTime.utc(anchor.year, anchor.month, anchor.day))
              .inDays,
        'weekly' =>
          DateTime.utc(due.year, due.month, due.day)
                  .difference(
                    DateTime.utc(anchor.year, anchor.month, anchor.day),
                  )
                  .inDays ~/
              7,
        'monthly' => (due.year - anchor.year) * 12 + due.month - anchor.month,
        'yearly' => due.year - anchor.year,
        _ => 0,
      };
      final base =
          record.kind.namespace + record.id * stride + (step % occurrences) * 2;
      final lead = DateTime(
        due.year,
        due.month,
        due.day - record.kind.leadDays,
        due.hour,
        due.minute,
        due.second,
      );
      final price = '₹${record.amount.toStringAsFixed(2)}';
      final title = switch (record.kind) {
        ReminderKind.payment => 'Payment due: ${record.name}',
        ReminderKind.subscription => 'Renewal soon: ${record.name}',
        ReminderKind.appliance => 'AMC renewal: ${record.name}',
      };
      final body = switch (record.kind) {
        ReminderKind.payment => '$price is due on ${due.day}/${due.month}.',
        ReminderKind.subscription =>
          '${record.name} ($price) renews on ${due.day}/${due.month}.',
        ReminderKind.appliance =>
          'The AMC for your ${record.brand} appliance expires on ${due.day}/${due.month}.',
      };
      if (lead.isAfter(now) || catchUp && result.isEmpty) {
        result.add(
          PlannedReminder(
            base,
            lead.isAfter(now) ? lead : now.add(const Duration(seconds: 5)),
            record.kind.channel,
            title,
            body,
          ),
        );
      }
      result.add(
        PlannedReminder(
          base + 1,
          due,
          record.kind.channel,
          switch (record.kind) {
            ReminderKind.payment => 'Payment due today: ${record.name}',
            ReminderKind.subscription => 'Renews today: ${record.name}',
            ReminderKind.appliance => 'AMC expires today: ${record.name}',
          },
          body,
        ),
      );
    }
    return result;
  }
}
