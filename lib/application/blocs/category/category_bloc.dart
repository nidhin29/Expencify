import '../../../domain/entities/category.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/repositories/category_repository.dart';
import 'category_event.dart';
import 'category_state.dart';

class CategoryBloc extends Bloc<CategoryEvent, CategoryState> {
  CategoryLoaded? _lastLoaded;
  int _loadRevision = 0;
  String? _loadedScope;
  final CategoryRepository _repository;
  List<Category> _lastCategories = [];

  CategoryBloc(this._repository) : super(CategoryInitial()) {
    on<LoadCategories>(_onLoadCategories);
    on<SaveCategory>(_onSaveCategory);
    on<DeleteCategory>(_onDeleteCategory);
  }

  Future<void> _onLoadCategories(
    LoadCategories event,
    Emitter<CategoryState> emit,
  ) async {
    final request = ++_loadRevision;
    final previous = _loadedScope == event.type
        ? (state is CategoryLoaded ? state as CategoryLoaded : _lastLoaded)
        : null;
    emit(
      previous == null
          ? CategoryLoading()
          : CategoryLoaded(previous.categories, refreshing: true),
    );
    try {
      final categories = await _repository.getAll(type: event.type);
      if (emit.isDone || request != _loadRevision) return;
      _lastCategories = categories;
      _loadedScope = event.type;
      emit(CategoryLoaded(categories));
      if (state is CategoryLoaded) _lastLoaded = state as CategoryLoaded;
    } catch (e) {
      if (emit.isDone || request != _loadRevision) return;
      emit(
        previous == null
            ? CategoryError('Could not load categories. Try again.')
            : CategoryLoaded(
                previous.categories,
                refreshError:
                    'Could not refresh. Your previous data is still shown.',
              ),
      );
    }
  }

  Future<void> _onSaveCategory(
    SaveCategory event,
    Emitter<CategoryState> emit,
  ) async {
    _loadRevision++;
    emit(CategoryMutating(_lastCategories));
    try {
      final id = await _repository.save(event.category);
      final value = event.category;
      final saved = Category(
        id: value.id ?? id,
        name: value.name,
        icon: value.icon,
        color: value.color,
        type: value.type,
      );
      final fallback = [
        ..._lastCategories.where((c) => c.id != saved.id),
        saved,
      ];
      // A failed refresh must not report a committed insert as failed: retrying
      // that insert would create a duplicate category.
      try {
        _lastCategories = await _repository.getAll();
      } catch (_) {
        _lastCategories = fallback;
      }
      emit(CategorySaved(_lastCategories, saved));
    } catch (e) {
      emit(CategoryError(e.toString()));
    }
  }

  Future<void> _onDeleteCategory(
    DeleteCategory event,
    Emitter<CategoryState> emit,
  ) async {
    _loadRevision++;
    emit(CategoryMutating(_lastCategories));
    try {
      await _repository.delete(event.id);
      final fallback = _lastCategories.where((c) => c.id != event.id).toList();
      try {
        _lastCategories = await _repository.getAll();
      } catch (_) {
        _lastCategories = fallback;
      }
      emit(CategoryDeleted(_lastCategories, event.id));
    } catch (e) {
      emit(CategoryError(e.toString()));
    }
  }
}
