import '../entities/goal.dart';

abstract class GoalRepository {
  Future<List<Goal>> getAll();
  Future<int> save(Goal goal); // insert or update
  Future<void> delete(int id);
  Future<void> addContribution(int goalId, double amount);
}
