import 'package:equatable/equatable.dart';
import '../../../domain/entities/account.dart';

abstract class AccountState extends Equatable {
  const AccountState();

  @override
  List<Object?> get props => [];
}

class AccountInitial extends AccountState {}

class AccountLoading extends AccountState {}

class AccountLoaded extends AccountState {
  final List<Account> accounts;
  final int? selectedAccountId;
  final double totalBalance;

  const AccountLoaded({
    required this.accounts,
    this.selectedAccountId,
    this.totalBalance = 0.0,
  });

  Account? get selectedAccount {
    if (selectedAccountId == null) return null;
    try {
      return accounts.firstWhere((a) => a.id == selectedAccountId);
    } catch (_) {
      return null;
    }
  }

  @override
  List<Object?> get props => [accounts, selectedAccountId, totalBalance];
}

class AccountError extends AccountState {
  final String message;
  const AccountError(this.message);

  @override
  List<Object?> get props => [message];
}
