import 'package:equatable/equatable.dart';

class SubscriptionModel extends Equatable {
  final int? id;
  final String name;
  final double amount;
  final String merchant;
  final DateTime startDate;
  final DateTime nextDueDate;
  final String frequency; // 'monthly', 'yearly'
  final bool isActive;
  final int accountId;

  const SubscriptionModel({
    this.id,
    required this.name,
    required this.amount,
    required this.merchant,
    required this.startDate,
    required this.nextDueDate,
    this.frequency = 'monthly',
    this.isActive = true,
    required this.accountId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'amount': amount,
      'merchant': merchant,
      'start_date': startDate.toIso8601String(),
      'next_due_date': nextDueDate.toIso8601String(),
      'frequency': frequency,
      'is_active': isActive ? 1 : 0,
      'account_id': accountId,
    };
  }

  factory SubscriptionModel.fromMap(Map<String, dynamic> map) {
    return SubscriptionModel(
      id: map['id'],
      name: map['name'],
      amount: (map['amount'] as num).toDouble(),
      merchant: map['merchant'] ?? '',
      startDate: DateTime.parse(map['start_date']),
      nextDueDate: DateTime.parse(map['next_due_date']),
      frequency: map['frequency'] ?? 'monthly',
      isActive: map['is_active'] == 1,
      accountId: map['account_id'],
    );
  }

  SubscriptionModel copyWith({
    int? id,
    String? name,
    double? amount,
    String? merchant,
    DateTime? startDate,
    DateTime? nextDueDate,
    String? frequency,
    bool? isActive,
    int? accountId,
  }) {
    return SubscriptionModel(
      id: id ?? this.id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      merchant: merchant ?? this.merchant,
      startDate: startDate ?? this.startDate,
      nextDueDate: nextDueDate ?? this.nextDueDate,
      frequency: frequency ?? this.frequency,
      isActive: isActive ?? this.isActive,
      accountId: accountId ?? this.accountId,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    amount,
    merchant,
    startDate,
    nextDueDate,
    frequency,
    isActive,
    accountId,
  ];
}
