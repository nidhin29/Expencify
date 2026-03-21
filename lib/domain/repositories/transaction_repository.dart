import '../entities/transaction.dart';

abstract class TransactionRepository {
  Future<List<TransactionModel>> getTransactions({
    int? accountId,
    String? type,
    String? category,
    DateTime? from,
    DateTime? to,
    String? search,
    int limit,
  });
  Future<int> save(TransactionModel transaction); // insert or update
  Future<TransactionModel?> getById(int id);
  Future<void> delete(int id);
  Future<Map<String, double>> getCategoryTotals({
    required String type,
    DateTime? from,
    DateTime? to,
    int? accountId,
  });
  Future<Map<String, double>> getDailyTotals({
    required String type,
    required DateTime from,
    required DateTime to,
    int? accountId,
  });
  Future<double> getMonthTotal(String type, {int? accountId});
  Future<double> getRangeTotal(
    String type, {
    DateTime? from,
    DateTime? to,
    int? accountId,
  });
  Future<List<TransactionModel>> getChildTransactions(int parentId);
  Future<Map<String, double>> getMonthlyTotals({int months});
  Future<Map<String, double>> getRangeMonthlyTotals({
    required String type,
    required DateTime from,
    required DateTime to,
  });
}
