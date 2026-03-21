import '../entities/budget.dart';

abstract class BudgetRepository {
  Future<List<Budget>> getAll({String? period});
  Future<int> save(Budget budget); // insert or update
  Future<void> delete(int id);
}
