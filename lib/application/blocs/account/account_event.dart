import 'package:equatable/equatable.dart';
import '../../../domain/entities/account.dart';

abstract class AccountEvent extends Equatable {
  const AccountEvent();

  @override
  List<Object?> get props => [];
}

class LoadAccounts extends AccountEvent {}

class SelectAccount extends AccountEvent {
  final int? id;
  const SelectAccount(this.id);

  @override
  List<Object?> get props => [id];
}

class AddAccount extends AccountEvent {
  final Account account;
  const AddAccount(this.account);

  @override
  List<Object?> get props => [account];
}

class UpdateAccount extends AccountEvent {
  final Account account;
  const UpdateAccount(this.account);

  @override
  List<Object?> get props => [account];
}

class DeleteAccount extends AccountEvent {
  final int id;
  const DeleteAccount(this.id);

  @override
  List<Object?> get props => [id];
}

class UpdateAccountBalance extends AccountEvent {
  final int accountId;
  final double delta;
  const UpdateAccountBalance(this.accountId, this.delta);

  @override
  List<Object?> get props => [accountId, delta];
}
