import '../refresh_status.dart';
import 'package:equatable/equatable.dart';
import '../../../domain/entities/goal.dart';

abstract class GoalState extends Equatable {
  const GoalState();

  @override
  List<Object?> get props => [];
}

class GoalInitial extends GoalState {}

class GoalLoading extends GoalState {}

class GoalLoaded extends GoalState implements RefreshStatus {
  @override
  final bool refreshing;
  @override
  final String? refreshError;
  final List<Goal> goals;
  const GoalLoaded(this.goals, {this.refreshing = false, this.refreshError});

  @override
  List<Object?> get props => [refreshing, refreshError, goals];
}

class GoalError extends GoalState {
  final String message;
  const GoalError(this.message);

  @override
  List<Object?> get props => [message];
}
