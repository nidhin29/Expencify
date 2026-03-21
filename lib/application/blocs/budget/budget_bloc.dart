import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/repositories/budget_repository.dart';
import 'budget_event.dart';
import 'budget_state.dart';

class BudgetBloc extends Bloc<BudgetEvent, BudgetState> {
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
    emit(BudgetLoading());
    try {
      final budgets = await _repository.getAll(period: event.period);
      emit(BudgetLoaded(budgets));
    } catch (e) {
      emit(BudgetError(e.toString()));
    }
  }

  Future<void> _onSaveBudget(
    SaveBudget event,
    Emitter<BudgetState> emit,
  ) async {
    try {
      await _repository.save(event.budget);
      add(const LoadBudgets());
    } catch (e) {
      emit(BudgetError(e.toString()));
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
