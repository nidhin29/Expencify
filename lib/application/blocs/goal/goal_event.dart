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
  const SaveGoal(this.goal);

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
  const AddGoalContribution(this.goalId, this.amount);

  @override
  List<Object?> get props => [goalId, amount];
}
