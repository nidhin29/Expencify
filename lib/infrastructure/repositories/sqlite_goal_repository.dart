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
    if (!amount.isFinite || amount > 1e12 || (amount * 100).round() <= 0) {
      throw ArgumentError('Invalid contribution.');
    }
    final cents = (amount * 100).round();
    final db = await _db.database;
    final changed = await db.rawUpdate(
      'UPDATE goals SET saved_amount = ROUND(COALESCE(saved_amount, 0) + ?, 2) WHERE id = ?',
      [cents / 100, goalId],
    );
    if (changed != 1) throw StateError('Goal no longer exists.');
  }
}
