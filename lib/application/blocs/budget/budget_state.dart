import '../refresh_status.dart';
import 'package:equatable/equatable.dart';
import '../../../domain/entities/budget.dart';

abstract class BudgetState extends Equatable {
  const BudgetState();

  @override
  List<Object?> get props => [];
}

class BudgetInitial extends BudgetState {}

class BudgetLoading extends BudgetState {}

class BudgetLoaded extends BudgetState implements RefreshStatus {
  @override
  final bool refreshing;
  @override
  final String? refreshError;
  final List<Budget> budgets;
  const BudgetLoaded(
    this.budgets, {
    this.refreshing = false,
    this.refreshError,
  });

  @override
  List<Object?> get props => [refreshing, refreshError, budgets];
}

class BudgetError extends BudgetState {
  final String message;
  const BudgetError(this.message);

  @override
  List<Object?> get props => [message];
}
