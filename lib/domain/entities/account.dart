import 'package:equatable/equatable.dart';

class Account extends Equatable {
  final int? id;
  final String name;
  final double balance;
  final String bankName;
  final String accountNumber;

  const Account({
    this.id,
    required this.name,
    required this.balance,
    required this.bankName,
    required this.accountNumber,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'balance': balance,
      'bank_name': bankName,
      'account_number': accountNumber,
    };
  }

  factory Account.fromMap(Map<String, dynamic> map) {
    return Account(
      id: map['id'],
      name: map['name'],
      balance: map['balance'],
      bankName: map['bank_name'],
      accountNumber: map['account_number'],
    );
  }

  Account copyWith({
    int? id,
    String? name,
    double? balance,
    String? bankName,
    String? accountNumber,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      balance: balance ?? this.balance,
      bankName: bankName ?? this.bankName,
      accountNumber: accountNumber ?? this.accountNumber,
    );
  }

  @override
  List<Object?> get props => [id, name, balance, bankName, accountNumber];
}
