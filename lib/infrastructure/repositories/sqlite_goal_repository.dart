import '../../domain/entities/goal.dart';
import '../../domain/repositories/goal_repository.dart';
import '../database/database_helper.dart';

class SqliteGoalRepository implements GoalRepository {
  final DatabaseHelper _db;

  SqliteGoalRepository(this._db);

  @override
  Future<List<Goal>> getAll() async {
    final rows = await _db.queryAll('goals');
    return rows.map(Goal.fromMap).toList();
  }

  @override
  Future<int> save(Goal goal) async {
    if (goal.id != null) {
      return await _db.update('goals', goal.toMap(), goal.id!);
    } else {
      return await _db.insert('goals', goal.toMap());
    }
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete('goals', id);
  }

  @override
  Future<void> addContribution(int goalId, double amount) async {
    await _db.rawUpdate(
      'UPDATE goals SET saved_amount = saved_amount + ? WHERE id = ?',
      [amount, goalId],
    );
  }
}
