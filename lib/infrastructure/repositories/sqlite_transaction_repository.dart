import '../../domain/entities/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../database/database_helper.dart';

class SqliteTransactionRepository implements TransactionRepository {
  final DatabaseHelper _db;

  SqliteTransactionRepository(this._db);

  @override
  Future<List<TransactionModel>> getTransactions({
    int? accountId,
    String? type,
    String? category,
    DateTime? from,
    DateTime? to,
    String? search,
    int limit = 200,
    bool hideSplits = true,
  }) async {
    String where = '1=1';
    List<dynamic> args = [];

    if (hideSplits) {
      where += ' AND parent_id IS NULL';
    }

    if (accountId != null) {
      where += ' AND account_id = ?';
      args.add(accountId);
    }
    if (type != null) {
      where += ' AND type = ?';
      args.add(type);
    }
    if (category != null) {
      where += ' AND LOWER(category) = LOWER(?)';
      args.add(category);
    }
    if (from != null) {
      where += ' AND date >= ?';
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where += ' AND date <= ?';
      args.add(to.toIso8601String());
    }
    if (search != null && search.isNotEmpty) {
      where += ' AND (note LIKE ? OR merchant LIKE ? OR category LIKE ?)';
      args.addAll(['%$search%', '%$search%', '%$search%']);
    }

    final db = await _db.database;
    final rows = await db.query(
      'transactions',
      where: where,
      whereArgs: args,
      orderBy: 'date DESC',
      limit: limit,
    );
    return rows.map(TransactionModel.fromMap).toList();
  }

  @override
  Future<TransactionModel?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TransactionModel.fromMap(rows.first);
  }

  @override
  Future<int> save(TransactionModel transaction) async {
    final map = transaction.toMap();
    if (map['category'] != null) {
      final cat = map['category'] as String;
      if (cat.isNotEmpty) {
        map['category'] = cat[0].toUpperCase() + cat.substring(1).toLowerCase();
      }
    }

    if (transaction.id != null) {
      return await _db.update('transactions', map, transaction.id!);
    } else {
      return await _db.insert('transactions', map);
    }
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete('transactions', where: 'parent_id = ?', whereArgs: [id]);
      await txn.delete('transactions', where: 'id = ?', whereArgs: [id]);
    });
  }

  @override
  Future<List<TransactionModel>> getChildTransactions(int parentId) async {
    final db = await _db.database;
    final rows = await db.query(
      'transactions',
      where: 'parent_id = ?',
      whereArgs: [parentId],
      orderBy: 'date ASC',
    );
    return rows.map(TransactionModel.fromMap).toList();
  }

  @override
  Future<Map<String, double>> getCategoryTotals({
    required String type,
    DateTime? from,
    DateTime? to,
    int? accountId,
  }) async {
    String where = 'type = ?';
    List<dynamic> args = [type];
    if (accountId != null) {
      where += ' AND account_id = ?';
      args.add(accountId);
    }
    if (from != null) {
      where += ' AND date >= ?';
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where += ' AND date <= ?';
      args.add(to.toIso8601String());
    }

    // Exclude parents if they have children (the children are the real expenses)
    where +=
        ' AND (id NOT IN (SELECT DISTINCT parent_id FROM transactions WHERE parent_id IS NOT NULL))';

    final rows = await _db.rawQuery(
      '''SELECT LOWER(category) as category, SUM(amount) as total 
         FROM transactions WHERE $where GROUP BY LOWER(category)''',
      args,
    );
    final Map<String, double> result = {};
    for (final row in rows) {
      final category = row['category'] as String? ?? 'Other';
      final display = category.isNotEmpty
          ? category[0].toUpperCase() + category.substring(1)
          : category;
      result[display] =
          (result[display] ?? 0.0) + (row['total'] as num).toDouble();
    }
    return result;
  }

  @override
  Future<Map<String, double>> getDailyTotals({
    required String type,
    required DateTime from,
    required DateTime to,
    int? accountId,
  }) async {
    String where = 'type = ? AND date >= ? AND date <= ? AND parent_id IS NULL';
    List<dynamic> args = [type, from.toIso8601String(), to.toIso8601String()];
    if (accountId != null) {
      where += ' AND account_id = ?';
      args.add(accountId);
    }
    final rows = await _db.rawQuery(
      '''SELECT DATE(date) as day, SUM(amount) as total
         FROM transactions
         WHERE $where
         GROUP BY day ORDER BY day''',
      args,
    );
    final Map<String, double> result = {};
    for (final row in rows) {
      result[row['day'] as String] = (row['total'] as num).toDouble();
    }
    return result;
  }

  @override
  Future<double> getMonthTotal(String type, {int? accountId}) async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, 1);
    String query =
        'SELECT SUM(amount) as total FROM transactions WHERE type=? AND date>=? AND parent_id IS NULL';
    List<dynamic> args = [type, from.toIso8601String()];
    if (accountId != null) {
      query += ' AND account_id = ?';
      args.add(accountId);
    }
    final rows = await _db.rawQuery(query, args);
    return (rows.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  @override
  Future<double> getRangeTotal(
    String type, {
    DateTime? from,
    DateTime? to,
    int? accountId,
  }) async {
    String where = 'type = ? AND parent_id IS NULL';
    List<dynamic> args = [type];

    if (accountId != null) {
      where += ' AND account_id = ?';
      args.add(accountId);
    }
    if (from != null) {
      where += ' AND date >= ?';
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where += ' AND date <= ?';
      args.add(to.toIso8601String());
    }

    final rows = await _db.rawQuery(
      'SELECT SUM(amount) as total FROM transactions WHERE $where',
      args,
    );
    return (rows.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  @override
  Future<Map<String, double>> getMonthlyTotals({int months = 6}) async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month - months + 1, 1);
    final rows = await _db.rawQuery(
      '''SELECT strftime('%Y-%m', date) as month, type, SUM(amount) as total 
         FROM transactions WHERE date >= ? AND parent_id IS NULL
         GROUP BY month, type ORDER BY month''',
      [from.toIso8601String()],
    );
    final Map<String, double> result = {};
    for (final row in rows) {
      final key = '${row['month']}_${row['type']}';
      result[key] = (row['total'] as num).toDouble();
    }
    return result;
  }

  @override
  Future<Map<String, double>> getRangeMonthlyTotals({
    required String type,
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _db.rawQuery(
      '''
      SELECT strftime('%Y-%m', date) as month, SUM(amount) as total 
      FROM transactions 
      WHERE type = ? AND date >= ? AND date <= ? AND parent_id IS NULL
      GROUP BY month
      ''',
      [type, from.toIso8601String(), to.toIso8601String()],
    );

    final Map<String, double> results = {};
    for (final row in rows) {
      results[row['month'] as String] =
          (row['total'] as num?)?.toDouble() ?? 0.0;
    }
    return results;
  }
}
