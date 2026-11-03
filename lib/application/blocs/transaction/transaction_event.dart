import 'dart:async';
import 'package:equatable/equatable.dart';
import '../../../domain/entities/transaction.dart';

abstract class TransactionEvent extends Equatable {
  const TransactionEvent();

  @override
  List<Object?> get props => [];
}

/// Refreshes current results without changing filters or removing the list.
class RefreshTransactions extends TransactionEvent {
  const RefreshTransactions();
}

class LoadTransactions extends TransactionEvent {
  final int? accountId;
  final String? type;
  final String? category;
  final DateTime? from;
  final DateTime? to;
  final String? search;
  final bool semantic;
  final bool silent; // ← Added to bypass emitting TransactionLoading spinner

  const LoadTransactions({
    this.accountId,
    this.type,
    this.category,
    this.from,
    this.to,
    this.search,
    this.silent = false,
    this.semantic = false,
  });

  @override
  List<Object?> get props => [
    accountId,
    type,
    category,
    from,
    to,
    search,
    silent,
    semantic,
  ];
}

class AddTransaction extends TransactionEvent {
  final TransactionModel transaction;
  final List<TransactionModel>? splitChildren;

  /// Optional acknowledgement of this mutation, independent of list refreshes.
  final Completer<bool>? completion;
  const AddTransaction(this.transaction, {this.splitChildren, this.completion});

  @override
  List<Object?> get props => [transaction, splitChildren];
}

class UpdateTransaction extends TransactionEvent {
  final TransactionModel transaction;
  final TransactionModel oldTransaction;
  final Completer<bool>? completion;
  const UpdateTransaction(
    this.transaction,
    this.oldTransaction, {
    this.completion,
  });

  @override
  List<Object?> get props => [transaction, oldTransaction];
}

class DeleteTransaction extends TransactionEvent {
  final TransactionModel transaction;
  const DeleteTransaction(this.transaction);

  @override
  List<Object?> get props => [transaction];
}

class SplitTransactions extends TransactionEvent {
  final TransactionModel original;
  final List<TransactionModel> parts;
  const SplitTransactions(this.original, this.parts);

  @override
  List<Object?> get props => [original, parts];
}
