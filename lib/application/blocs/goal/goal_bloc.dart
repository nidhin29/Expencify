import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/repositories/goal_repository.dart';
import 'goal_event.dart';
import 'goal_state.dart';

class GoalBloc extends Bloc<GoalEvent, GoalState> {
  final GoalRepository _repository;

  GoalBloc(this._repository) : super(GoalInitial()) {
    on<LoadGoals>(_onLoadGoals);
    on<SaveGoal>(_onSaveGoal);
    on<DeleteGoal>(_onDeleteGoal);
    on<AddGoalContribution>(_onAddGoalContribution);
  }

  Future<void> _onLoadGoals(LoadGoals event, Emitter<GoalState> emit) async {
    emit(GoalLoading());
    try {
      final goals = await _repository.getAll();
      emit(GoalLoaded(goals));
    } catch (e) {
      emit(GoalError(e.toString()));
    }
  }

  Future<void> _onSaveGoal(SaveGoal event, Emitter<GoalState> emit) async {
    try {
      await _repository.save(event.goal);
      add(LoadGoals());
    } catch (e) {
      emit(GoalError(e.toString()));
    }
  }

  Future<void> _onDeleteGoal(DeleteGoal event, Emitter<GoalState> emit) async {
    try {
      await _repository.delete(event.id);
      add(LoadGoals());
    } catch (e) {
      emit(GoalError(e.toString()));
    }
  }

  Future<void> _onAddGoalContribution(
    AddGoalContribution event,
    Emitter<GoalState> emit,
  ) async {
    try {
      await _repository.addContribution(event.goalId, event.amount);
      add(LoadGoals());
    } catch (e) {
      emit(GoalError(e.toString()));
    }
  }
}
