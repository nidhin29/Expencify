import '../refresh_status.dart';
import 'package:equatable/equatable.dart';
import '../../../domain/entities/transaction.dart';

abstract class TransactionState extends Equatable {
  const TransactionState();

  @override
  List<Object?> get props => [];
}

class TransactionInitial extends TransactionState {}

class TransactionLoading extends TransactionState {}

class TransactionLoaded extends TransactionState implements RefreshStatus {
  @override
  final bool refreshing;
  @override
  final String? refreshError;
  final List<TransactionModel> transactions;

  const TransactionLoaded(
    this.transactions, {
    this.refreshing = false,
    this.refreshError,
  });

  @override
  List<Object?> get props => [transactions, refreshing, refreshError];
}

class TransactionError extends TransactionState {
  final String message;
  const TransactionError(this.message);

  @override
  List<Object?> get props => [message];
}
