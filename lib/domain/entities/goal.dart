import 'package:equatable/equatable.dart';

class Goal extends Equatable {
  final int? id;
  final String name;
  final double targetAmount;
  final double savedAmount;
  final DateTime targetDate;
  final String icon;
  final int color;
  final int? accountId;

  const Goal({
    this.id,
    required this.name,
    required this.targetAmount,
    this.savedAmount = 0,
    required this.targetDate,
    this.icon = 'savings',
    this.color = 0xFF6366F1,
    this.accountId,
  });

  double get progress =>
      targetAmount > 0 ? (savedAmount / targetAmount).clamp(0.0, 1.0) : 0.0;
  bool get isCompleted => savedAmount >= targetAmount;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'target_amount': targetAmount,
      'saved_amount': savedAmount,
      'target_date': targetDate.toIso8601String(),
      'icon': icon,
      'color': color,
      'account_id': accountId,
    };
  }

  factory Goal.fromMap(Map<String, dynamic> map) {
    return Goal(
      id: map['id'],
      name: map['name'],
      targetAmount: map['target_amount'],
      savedAmount: map['saved_amount'] ?? 0,
      targetDate: DateTime.parse(map['target_date']),
      icon: map['icon'] ?? 'savings',
      color: map['color'] ?? 0xFF6366F1,
      accountId: map['account_id'],
    );
  }

  Goal copyWith({double? savedAmount}) {
    return Goal(
      id: id,
      name: name,
      targetAmount: targetAmount,
      savedAmount: savedAmount ?? this.savedAmount,
      targetDate: targetDate,
      icon: icon,
      color: color,
      accountId: accountId,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    targetAmount,
    savedAmount,
    targetDate,
    icon,
    color,
    accountId,
  ];
}
