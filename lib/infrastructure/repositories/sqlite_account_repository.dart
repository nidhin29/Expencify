import '../../domain/entities/account.dart';
import '../../domain/repositories/account_repository.dart';
import '../database/database_helper.dart';

class SqliteAccountRepository implements AccountRepository {
  final DatabaseHelper _db;

  SqliteAccountRepository(this._db);

  @override
  Future<List<Account>> getAll() async {
    final rows = await _db.queryAll('accounts');
    return rows.map(Account.fromMap).toList();
  }

  @override
  Future<int> save(Account account) async {
    if (account.id != null) {
      return await _db.update('accounts', account.toMap(), account.id!);
    } else {
      return await _db.insert('accounts', account.toMap());
    }
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete('accounts', id);
  }

  @override
  Future<void> updateBalance(int accountId, double delta) async {
    await _db.rawUpdate(
      'UPDATE accounts SET balance = balance + ? WHERE id = ?',
      [delta, accountId],
    );
  }

  @override
  Future<double> getTotalBalance({int? accountId}) async {
    if (accountId != null) {
      final res = await _db.rawQuery(
        'SELECT balance FROM accounts WHERE id = ?',
        [accountId],
      );
      // Guard: account may have been deleted (e.g. after wipe)
      if (res.isEmpty) return 0.0;
      return (res.first['balance'] as num?)?.toDouble() ?? 0.0;
    }
    final result = await _db.rawQuery(
      'SELECT SUM(balance) as total FROM accounts',
    );
    if (result.isEmpty) return 0.0;
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }
}
