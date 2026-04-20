import '../../domain/entities/subscription.dart';
import '../../domain/repositories/subscription_repository.dart';
import '../database/database_helper.dart';

class SqliteSubscriptionRepository implements SubscriptionRepository {
  final DatabaseHelper _dbHelper;

  SqliteSubscriptionRepository(this._dbHelper);

  @override
  Future<List<SubscriptionModel>> getAll({bool? activeOnly}) async {
    final db = await _dbHelper.database;
    String? where;
    List<dynamic>? whereArgs;

    if (activeOnly != null) {
      where = 'is_active = ?';
      whereArgs = [activeOnly ? 1 : 0];
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'subscriptions',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'next_due_date ASC',
    );

    return List.generate(maps.length, (i) => SubscriptionModel.fromMap(maps[i]));
  }

  @override
  Future<int> save(SubscriptionModel subscription) async {
    final db = await _dbHelper.database;
    if (subscription.id != null) {
      await db.update(
        'subscriptions',
        subscription.toMap(),
        where: 'id = ?',
        whereArgs: [subscription.id],
      );
      return subscription.id!;
    } else {
      return await db.insert('subscriptions', subscription.toMap());
    }
  }

  @override
  Future<void> delete(int id) async {
    final db = await _dbHelper.database;
    await db.delete('subscriptions', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<SubscriptionModel>> findPotentialSubscriptions() async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    final ninetyDaysAgo = now.subtract(const Duration(days: 90));

    // Get all expense transactions in last 90 days
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'type = ? AND date >= ? AND parent_id IS NULL',
      whereArgs: ['expense', ninetyDaysAgo.toIso8601String()],
      orderBy: 'date DESC',
    );

    if (maps.length < 2) return [];

    // Group by merchant
    final Map<String, List<Map<String, dynamic>>> groups = {};
    for (final m in maps) {
      final merchant = m['merchant'] as String? ?? 'Unknown';
      if (merchant.isEmpty || merchant == 'Unknown') continue;
      groups.putIfAbsent(merchant, () => []).add(m);
    }

    final List<SubscriptionModel> potentials = [];

    // Check for recurring patterns
    groups.forEach((merchant, txs) {
      if (txs.length < 2) return;

      // Sort by date ASC for interval checking
      txs.sort((a, b) => a['date'].compareTo(b['date']));

      bool isRecurring = false;
      double avgAmount = 0;

      for (int i = 0; i < txs.length - 1; i++) {
        final d1 = DateTime.parse(txs[i]['date']);
        final d2 = DateTime.parse(txs[i + 1]['date']);
        final diff = d2.difference(d1).inDays;

        // Roughly monthly (27-33 days)
        if (diff >= 27 && diff <= 33) {
          final a1 = txs[i]['amount'] as double;
          final a2 = txs[i + 1]['amount'] as double;
          
          // Similar amounts (within 10%)
          if ((a1 - a2).abs() / a1 < 0.1) {
            isRecurring = true;
            avgAmount = (a1 + a2) / 2;
          }
        }
      }

      if (isRecurring) {
        // Suggest a subscription
        final lastDate = DateTime.parse(txs.last['date']);
        potentials.add(
          SubscriptionModel(
            name: merchant,
            amount: avgAmount,
            merchant: merchant,
            startDate: DateTime.parse(txs.first['date']),
            nextDueDate: lastDate.add(const Duration(days: 30)),
            accountId: txs.last['account_id'],
            frequency: 'monthly',
          ),
        );
      }
    });

    // Filter out already tracked subscriptions
    final tracked = await getAll();
    final trackedMerchants = tracked.map((s) => s.merchant.toLowerCase()).toSet();

    return potentials.where((p) => !trackedMerchants.contains(p.merchant.toLowerCase())).toList();
  }
}
