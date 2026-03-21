import '../../domain/entities/category.dart';
import '../../domain/repositories/category_repository.dart';
import '../database/database_helper.dart';

class SqliteCategoryRepository implements CategoryRepository {
  final DatabaseHelper _db;

  SqliteCategoryRepository(this._db);

  @override
  Future<List<Category>> getAll({String? type}) async {
    final db = await _db.database;
    final rows = type != null
        ? await db.query('categories', where: 'type = ?', whereArgs: [type])
        : await db.query('categories');
    return rows.map(Category.fromMap).toList();
  }

  @override
  Future<int> save(Category category) async {
    if (category.id != null) {
      return await _db.update('categories', category.toMap(), category.id!);
    } else {
      return await _db.insert('categories', category.toMap());
    }
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete('categories', id);
  }
}
