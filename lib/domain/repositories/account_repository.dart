import '../entities/account.dart';

abstract class AccountRepository {
  Future<List<Account>> getAll();
  Future<int> save(Account account); // insert or update
  Future<void> delete(int id);
  Future<void> updateBalance(int accountId, double delta);
  Future<double> getTotalBalance({int? accountId});
}
