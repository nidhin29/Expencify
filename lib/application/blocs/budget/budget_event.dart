import 'dart:async';
import 'package:equatable/equatable.dart';
import '../../../domain/entities/budget.dart';

abstract class BudgetEvent extends Equatable {
  const BudgetEvent();

  @override
  List<Object?> get props => [];
}

class LoadBudgets extends BudgetEvent {
  final String? period;
  const LoadBudgets({this.period});

  @override
  List<Object?> get props => [period];
}

class SaveBudget extends BudgetEvent {
  final Budget budget;
  final Completer<bool>? completion;
  const SaveBudget(this.budget, {this.completion});

  @override
  List<Object?> get props => [budget];
}

class DeleteBudget extends BudgetEvent {
  final int id;
  const DeleteBudget(this.id);

  @override
  List<Object?> get props => [id];
}
