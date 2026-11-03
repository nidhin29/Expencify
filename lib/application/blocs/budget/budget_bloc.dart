import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/repositories/budget_repository.dart';
import 'budget_event.dart';
import 'budget_state.dart';

class BudgetBloc extends Bloc<BudgetEvent, BudgetState> {
  BudgetLoaded? _lastLoaded;
  int _loadRevision = 0;
  String? _loadedScope;
  final BudgetRepository _repository;

  BudgetBloc(this._repository) : super(BudgetInitial()) {
    on<LoadBudgets>(_onLoadBudgets);
    on<SaveBudget>(_onSaveBudget);
    on<DeleteBudget>(_onDeleteBudget);
  }

  Future<void> _onLoadBudgets(
    LoadBudgets event,
    Emitter<BudgetState> emit,
  ) async {
    final request = ++_loadRevision;
    final previous = _loadedScope == event.period
        ? (state is BudgetLoaded ? state as BudgetLoaded : _lastLoaded)
        : null;
    emit(
      previous == null
          ? BudgetLoading()
          : BudgetLoaded(previous.budgets, refreshing: true),
    );
    try {
      final budgets = await _repository.getAll(period: event.period);
      if (emit.isDone || request != _loadRevision) return;
      _loadedScope = event.period;
      emit(BudgetLoaded(budgets));
      if (state is BudgetLoaded) _lastLoaded = state as BudgetLoaded;
    } catch (e) {
      if (emit.isDone || request != _loadRevision) return;
      emit(
        previous == null
            ? BudgetError('Could not load budgets. Try again.')
            : BudgetLoaded(
                previous.budgets,
                refreshError:
                    'Could not refresh. Your previous data is still shown.',
              ),
      );
    }
  }

  Future<void> _onSaveBudget(
    SaveBudget event,
    Emitter<BudgetState> emit,
  ) async {
    var persisted = false;
    try {
      await _repository.save(event.budget);
      persisted = true;
      add(const LoadBudgets());
    } catch (e) {
      emit(BudgetError(e.toString()));
    } finally {
      final completion = event.completion;
      if (completion != null && !completion.isCompleted) {
        completion.complete(persisted);
      }
    }
  }

  Future<void> _onDeleteBudget(
    DeleteBudget event,
    Emitter<BudgetState> emit,
  ) async {
    try {
      await _repository.delete(event.id);
      add(const LoadBudgets());
    } catch (e) {
      emit(BudgetError(e.toString()));
    }
  }
}
