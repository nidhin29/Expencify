import '../entities/transaction.dart';

abstract class TransactionRepository {
  Future<List<TransactionModel>> getTransactions({
    int? accountId,
    String? type,
    String? category,
    DateTime? from,
    DateTime? to,
    String? search,
    int? limit,
    bool hideSplits,
    bool leafOnly,
  });

  /// Saves the record and its balance effect atomically.
  Future<int> save(TransactionModel transaction);

  /// Saves an edit and renames exact old-merchant matches atomically.
  Future<void> saveWithMerchantRename(TransactionModel transaction);
  Future<int> saveWithChildren(
    TransactionModel transaction,
    List<TransactionModel> children,
  );
  Future<void> replaceSplits(int parentId, List<TransactionModel> children);
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
