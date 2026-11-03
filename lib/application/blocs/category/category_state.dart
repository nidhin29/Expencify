import '../refresh_status.dart';
import 'package:equatable/equatable.dart';
import '../../../domain/entities/category.dart';

abstract class CategoryState extends Equatable {
  const CategoryState();

  @override
  List<Object?> get props => [];
}

class CategoryInitial extends CategoryState {}

class CategoryLoading extends CategoryState {}

class CategoryLoaded extends CategoryState implements RefreshStatus {
  @override
  final bool refreshing;
  @override
  final String? refreshError;
  final List<Category> categories;
  const CategoryLoaded(
    this.categories, {
    this.refreshing = false,
    this.refreshError,
  });

  @override
  List<Object?> get props => [refreshing, refreshError, categories];
}

class CategoryError extends CategoryState {
  final String message;
  const CategoryError(this.message);

  @override
  List<Object?> get props => [message];
}

class CategorySaved extends CategoryLoaded {
  final Category saved;
  const CategorySaved(super.categories, this.saved);
  @override
  List<Object?> get props => [categories, saved];
}

class CategoryDeleted extends CategoryLoaded {
  final int deletedId;
  const CategoryDeleted(super.categories, this.deletedId);
  @override
  List<Object?> get props => [categories, deletedId];
}

class CategoryMutating extends CategoryLoaded {
  const CategoryMutating(super.categories);
}
