import 'dart:async';
import 'package:equatable/equatable.dart';
import '../../../domain/entities/goal.dart';

abstract class GoalEvent extends Equatable {
  const GoalEvent();

  @override
  List<Object?> get props => [];
}

class LoadGoals extends GoalEvent {}

class SaveGoal extends GoalEvent {
  final Goal goal;
  final Completer<bool>? completion;
  const SaveGoal(this.goal, {this.completion});

  @override
  List<Object?> get props => [goal];
}

class DeleteGoal extends GoalEvent {
  final int id;
  const DeleteGoal(this.id);

  @override
  List<Object?> get props => [id];
}

class AddGoalContribution extends GoalEvent {
  final int goalId;
  final double amount;
  final Completer<bool>? completion;
  const AddGoalContribution(this.goalId, this.amount, {this.completion});

  @override
  List<Object?> get props => [goalId, amount];
}
