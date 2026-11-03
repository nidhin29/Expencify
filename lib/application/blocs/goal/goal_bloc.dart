import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/repositories/goal_repository.dart';
import 'goal_event.dart';
import 'goal_state.dart';

class GoalBloc extends Bloc<GoalEvent, GoalState> {
  GoalLoaded? _lastLoaded;
  int _loadRevision = 0;
  final GoalRepository _repository;

  GoalBloc(this._repository) : super(GoalInitial()) {
    on<LoadGoals>(_onLoadGoals);
    on<SaveGoal>(_onSaveGoal);
    on<DeleteGoal>(_onDeleteGoal);
    on<AddGoalContribution>(_onAddGoalContribution);
  }

  Future<void> _onLoadGoals(LoadGoals event, Emitter<GoalState> emit) async {
    final request = ++_loadRevision;
    final previous = state is GoalLoaded ? state as GoalLoaded : _lastLoaded;
    emit(
      previous == null
          ? GoalLoading()
          : GoalLoaded(previous.goals, refreshing: true),
    );
    try {
      final goals = await _repository.getAll();
      if (emit.isDone || request != _loadRevision) return;
      emit(GoalLoaded(goals));
      if (state is GoalLoaded) _lastLoaded = state as GoalLoaded;
    } catch (e) {
      if (emit.isDone || request != _loadRevision) return;
      emit(
        previous == null
            ? GoalError('Could not load goals. Try again.')
            : GoalLoaded(
                previous.goals,
                refreshError:
                    'Could not refresh. Your previous data is still shown.',
              ),
      );
    }
  }

  Future<void> _onSaveGoal(SaveGoal event, Emitter<GoalState> emit) async {
    var persisted = false;
    try {
      await _repository.save(event.goal);
      persisted = true;
      add(LoadGoals());
    } catch (e) {
      emit(GoalError(e.toString()));
    } finally {
      final completion = event.completion;
      if (completion != null && !completion.isCompleted) {
        completion.complete(persisted);
      }
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
    var persisted = false;
    try {
      await _repository.addContribution(event.goalId, event.amount);
      persisted = true;
      add(LoadGoals());
    } catch (e) {
      emit(GoalError(e.toString()));
    } finally {
      final completion = event.completion;
      if (completion != null && !completion.isCompleted) {
        completion.complete(persisted);
      }
    }
  }
}
