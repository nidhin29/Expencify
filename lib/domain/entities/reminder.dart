import 'package:equatable/equatable.dart';

class Reminder extends Equatable {
  final int? id;
  final String title;
  final double amount;
  final DateTime dueDate;
  final DateTime? recurrenceAnchor;
  final bool isRecurring;
  final String frequency; // 'monthly', 'weekly', 'yearly', 'once'

  const Reminder({
    this.id,
    required this.title,
    required this.amount,
    required this.dueDate,
    this.recurrenceAnchor,
    this.isRecurring = false,
    this.frequency = 'monthly',
  });

  bool get isDueSoon =>
      dueDate.difference(DateTime.now()).inDays <= 3 &&
      dueDate.isAfter(DateTime.now());
  bool get isOverdue => dueDate.isBefore(DateTime.now());
  int get daysUntilExpiry => dueDate.difference(DateTime.now()).inDays;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'amount': amount,
      'due_date': dueDate.toIso8601String(),
      'recurrence_anchor': recurrenceAnchor?.toIso8601String(),
      'is_recurring': isRecurring ? 1 : 0,
      'frequency': frequency,
    };
  }

  factory Reminder.fromMap(Map<String, dynamic> map) {
    return Reminder(
      id: map['id'],
      title: map['title'],
      amount: map['amount'],
      dueDate: DateTime.parse(map['due_date']),
      recurrenceAnchor: map['recurrence_anchor'] == null
          ? null
          : DateTime.parse(map['recurrence_anchor']),
      isRecurring: map['is_recurring'] == 1,
      frequency: map['frequency'] ?? 'monthly',
    );
  }

  @override
  List<Object?> get props => [
    id,
    title,
    amount,
    dueDate,
    recurrenceAnchor,
    isRecurring,
    frequency,
  ];
}
