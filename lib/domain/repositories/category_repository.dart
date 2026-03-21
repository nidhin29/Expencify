import '../entities/category.dart';

abstract class CategoryRepository {
  Future<List<Category>> getAll({String? type});
  Future<int> save(Category category); // insert or update
  Future<void> delete(int id);
}
