import '../../domain/entities/budget.dart';
import '../../domain/repositories/budget_repository.dart';
import '../database/database_helper.dart';

class SqliteBudgetRepository implements BudgetRepository {
  final DatabaseHelper _db;

  SqliteBudgetRepository(this._db);

  @override
  Future<List<Budget>> getAll({String? period}) async {
    if (period != null) {
      final db = await _db.database;
      final rows = await db.query(
        'budgets',
        where: 'period = ?',
        whereArgs: [period],
      );
      return rows.map(Budget.fromMap).toList();
    }
    final rows = await _db.queryAll('budgets');
    return rows.map(Budget.fromMap).toList();
  }

  @override
  Future<int> save(Budget budget) async {
    if (budget.id != null) {
      return await _db.update('budgets', budget.toMap(), budget.id!);
    } else {
      return await _db.insert('budgets', budget.toMap());
    }
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete('budgets', id);
  }
}
