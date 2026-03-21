import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/repositories/category_repository.dart';
import 'category_event.dart';
import 'category_state.dart';

class CategoryBloc extends Bloc<CategoryEvent, CategoryState> {
  final CategoryRepository _repository;

  CategoryBloc(this._repository) : super(CategoryInitial()) {
    on<LoadCategories>(_onLoadCategories);
    on<SaveCategory>(_onSaveCategory);
    on<DeleteCategory>(_onDeleteCategory);
  }

  Future<void> _onLoadCategories(
    LoadCategories event,
    Emitter<CategoryState> emit,
  ) async {
    emit(CategoryLoading());
    try {
      final categories = await _repository.getAll(type: event.type);
      emit(CategoryLoaded(categories));
    } catch (e) {
      emit(CategoryError(e.toString()));
    }
  }

  Future<void> _onSaveCategory(
    SaveCategory event,
    Emitter<CategoryState> emit,
  ) async {
    try {
      await _repository.save(event.category);
      add(LoadCategories(type: event.category.type));
    } catch (e) {
      emit(CategoryError(e.toString()));
    }
  }

  Future<void> _onDeleteCategory(
    DeleteCategory event,
    Emitter<CategoryState> emit,
  ) async {
    try {
      await _repository.delete(event.id);
      add(const LoadCategories());
    } catch (e) {
      emit(CategoryError(e.toString()));
    }
  }
}
