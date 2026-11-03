import 'dart:async';
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
  final Completer<bool>? completion;
  const AddAccount(this.account, {this.completion});

  @override
  List<Object?> get props => [account];
}

class UpdateAccount extends AccountEvent {
  final Account account;
  final Completer<bool>? completion;
  const UpdateAccount(this.account, {this.completion});

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
