import 'package:equatable/equatable.dart';

class Budget extends Equatable {
  final int? id;
  final String category;
  final double amount;
  final String period; // 'weekly', 'monthly', 'yearly'
  final DateTime startDate;
  final int? accountId;

  const Budget({
    this.id,
    required this.category,
    required this.amount,
    required this.period,
    required this.startDate,
    this.accountId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category,
      'amount': amount,
      'period': period,
      'start_date': startDate.toIso8601String(),
      'account_id': accountId,
    };
  }

  factory Budget.fromMap(Map<String, dynamic> map) {
    return Budget(
      id: map['id'],
      category: map['category'],
      amount: map['amount'],
      period: map['period'],
      startDate: DateTime.parse(map['start_date']),
      accountId: map['account_id'],
    );
  }

  @override
  List<Object?> get props => [
    id,
    category,
    amount,
    period,
    startDate,
    accountId,
  ];
}
