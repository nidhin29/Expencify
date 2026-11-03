import '../../application/services/performance/performance_probe.dart';
import 'dart:math' as math;
import 'package:sqflite/sqflite.dart';
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
    int? limit,
    bool hideSplits = true,
    bool leafOnly = false,
  }) async {
    String where = '1=1';
    List<dynamic> args = [];

    if (leafOnly) {
      where +=
          ' AND id NOT IN (SELECT parent_id FROM transactions WHERE parent_id IS NOT NULL)';
    } else if (hideSplits) {
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
    return PerformanceProbe.measure('database.transactions.read', () async {
      final rows = await db.query(
        'transactions',
        where: where,
        whereArgs: args,
        orderBy: 'date DESC',
        limit: limit,
      );
      return rows.map(TransactionModel.fromMap).toList();
    });
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

  double _effect(TransactionModel t) =>
      t.type == 'income' ? t.amount : -t.amount;

  void _validate(TransactionModel t) {
    if (!t.amount.isFinite ||
        (t.amount * 100).round() <= 0 ||
        !['income', 'expense'].contains(t.type)) {
      throw ArgumentError(
        'Enter a positive amount and a valid transaction type.',
      );
    }
  }

  Future<TransactionModel?> _find(DatabaseExecutor txn, int id) async {
    final rows = await txn.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : TransactionModel.fromMap(rows.first);
  }

  Future<void> _balance(
    DatabaseExecutor txn,
    int accountId,
    double delta,
  ) async {
    final count = await txn.rawUpdate(
      'UPDATE accounts SET balance = balance + ? WHERE id = ?',
      [delta, accountId],
    );
    if (count != 1) throw StateError('The selected account no longer exists.');
  }

  Future<int> _save(DatabaseExecutor txn, TransactionModel value) async {
    _validate(value);
    final old = value.id == null ? null : await _find(txn, value.id!);
    if (value.id != null && old == null) {
      throw StateError('Transaction no longer exists.');
    }
    if (old != null && old.parentId != value.parentId) {
      throw ArgumentError('Cannot reparent a transaction.');
    }
    var t = value.copyWith(amount: (value.amount * 100).round() / 100);
    if (t.parentId != null) {
      final parent = await _find(txn, t.parentId!);
      if (parent == null || parent.parentId != null) {
        throw StateError('Invalid split parent.');
      }
      t = t.copyWith(
        accountId: parent.accountId,
        date: parent.date,
        type: parent.type,
      );
      final difference = t.amount - (old?.amount ?? 0);
      await txn.update(
        'transactions',
        {'amount': parent.amount + difference},
        where: 'id = ?',
        whereArgs: [parent.id],
      );
      await _balance(
        txn,
        parent.accountId,
        parent.type == 'income' ? difference : -difference,
      );
    } else {
      if (old != null) await _balance(txn, old.accountId, -_effect(old));
      await _balance(txn, t.accountId, _effect(t));
    }
    final map = t.toMap();
    final id = old == null ? await txn.insert('transactions', map) : old.id!;
    if (old != null) {
      await txn.update('transactions', map, where: 'id = ?', whereArgs: [id]);
    }
    if (old != null && t.parentId == null) {
      final children = await txn.query(
        'transactions',
        where: 'parent_id = ?',
        whereArgs: [id],
      );
      if (children.isNotEmpty) {
        // Allocate integer cents proportionally. The final child receives the remainder.
        final total = children.fold<int>(
          0,
          (sum, row) => sum + ((row['amount'] as num) * 100).round(),
        );
        var remaining = (t.amount * 100).round();
        for (var i = 0; i < children.length; i++) {
          final row = children[i];
          final cents = i == children.length - 1
              ? remaining
              : math.min(
                  remaining,
                  ((t.amount * 100).round() *
                          ((row['amount'] as num) * 100).round()) ~/
                      total,
                );
          remaining -= cents;
          if (cents == 0) {
            await txn.delete(
              'transactions',
              where: 'id = ?',
              whereArgs: [row['id']],
            );
          } else {
            await txn.update(
              'transactions',
              {
                'amount': cents / 100,
                'account_id': t.accountId,
                'date': t.date.toIso8601String(),
                'type': t.type,
              },
              where: 'id = ?',
              whereArgs: [row['id']],
            );
          }
        }
      }
    }
    return id;
  }

  @override
  Future<int> save(TransactionModel transaction) async {
    final db = await _db.database;
    return db.transaction((txn) => _save(txn, transaction));
  }

  @override
  Future<void> saveWithMerchantRename(TransactionModel transaction) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      if (transaction.id == null) {
        throw ArgumentError('An existing transaction is required.');
      }
      final old = await _find(txn, transaction.id!);
      if (old == null) throw StateError('Transaction no longer exists.');
      final before = old.merchant.trim();
      final after = transaction.merchant.trim();
      await _save(txn, transaction.copyWith(merchant: after));
      if (before.isEmpty || after.isEmpty || before == after) return;
      await txn.rawUpdate(
        'UPDATE transactions SET merchant = ? WHERE lower(trim(merchant)) = lower(?)',
        [after, before],
      );
      // Existing recognition rules follow the corrected display name, retaining
      // their SMS keyword, category and direction.
      await txn.rawUpdate(
        'UPDATE registered_entities SET name = ? WHERE lower(trim(name)) = lower(?)',
        [after, before],
      );
    });
  }

  /// The durable identity and financial mutation commit together, across isolates.
  Future<bool> saveSms(TransactionModel transaction, String identity) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final existing = await txn.query(
        'processed_sms_log',
        where: 'body = ?',
        whereArgs: [identity],
        limit: 1,
      );
      if (existing.isNotEmpty) return false;
      await _save(txn, transaction);
      await txn.delete(
        'sms_review',
        where: 'identity = ?',
        whereArgs: [identity],
      );
      await txn.insert('processed_sms_log', {
        'body': identity,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      return true;
    });
  }

  Future<void> _splits(
    DatabaseExecutor txn,
    int parentId,
    List<TransactionModel> children,
  ) async {
    final parent = await _find(txn, parentId);
    if (parent == null || parent.parentId != null) {
      throw StateError('Invalid split parent.');
    }
    if (children.isNotEmpty) {
      for (final child in children) {
        _validate(child);
      }
      final cents = children.fold<int>(
        0,
        (sum, child) => sum + (child.amount * 100).round(),
      );
      if (cents != (parent.amount * 100).round()) {
        throw ArgumentError('Split amounts must equal the total.');
      }
    }
    await txn.delete(
      'transactions',
      where: 'parent_id = ?',
      whereArgs: [parentId],
    );
    for (final child in children) {
      final map =
          child
              .copyWith(
                amount: (child.amount * 100).round() / 100,
                accountId: parent.accountId,
                date: parent.date,
                type: parent.type,
                parentId: parentId,
              )
              .toMap()
            ..remove('id');
      await txn.insert('transactions', map);
    }
  }

  @override
  Future<int> saveWithChildren(
    TransactionModel transaction,
    List<TransactionModel> children,
  ) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final id = await _save(txn, transaction);
      if (transaction.parentId == null) await _splits(txn, id, children);
      return id;
    });
  }

  @override
  Future<void> replaceSplits(
    int parentId,
    List<TransactionModel> children,
  ) async {
    final db = await _db.database;
    await db.transaction((txn) => _splits(txn, parentId, children));
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final t = await _find(txn, id);
      if (t == null) return;
      if (t.parentId != null) {
        final parent = await _find(txn, t.parentId!);
        if (parent == null) throw StateError('Split parent missing.');
        final remaining = ((parent.amount - t.amount) * 100).round();
        if (remaining <= 0) {
          await txn.delete(
            'transactions',
            where: 'id = ?',
            whereArgs: [parent.id],
          );
        } else {
          await txn.update(
            'transactions',
            {'amount': remaining / 100},
            where: 'id = ?',
            whereArgs: [parent.id],
          );
        }
      }
      await _balance(txn, t.accountId, -_effect(t));
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
        'SELECT SUM(amount) as total FROM transactions WHERE type=? AND date>=? AND date<? AND parent_id IS NULL';
    List<dynamic> args = [
      type,
      from.toIso8601String(),
      DateTime(now.year, now.month + 1).toIso8601String(),
    ];
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
