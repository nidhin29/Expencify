import 'package:equatable/equatable.dart';
import '../../../domain/entities/category.dart';

abstract class CategoryEvent extends Equatable {
  const CategoryEvent();

  @override
  List<Object?> get props => [];
}

class LoadCategories extends CategoryEvent {
  final String? type;
  const LoadCategories({this.type});

  @override
  List<Object?> get props => [type];
}

class SaveCategory extends CategoryEvent {
  final Category category;
  const SaveCategory(this.category);

  @override
  List<Object?> get props => [category];
}

class DeleteCategory extends CategoryEvent {
  final int id;
  const DeleteCategory(this.id);

  @override
  List<Object?> get props => [id];
}
