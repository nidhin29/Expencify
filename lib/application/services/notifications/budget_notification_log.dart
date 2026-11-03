import 'package:sqflite/sqflite.dart';

Future<bool> claimBudgetNotification(
  Database db,
  String key,
  DateTime now,
) async {
  await db.execute(
    'CREATE TABLE IF NOT EXISTS budget_update_log (delivery_key TEXT PRIMARY KEY, created_at TEXT NOT NULL)',
  );
  return db.transaction((txn) async {
    await txn.rawInsert(
      'INSERT OR IGNORE INTO budget_update_log(delivery_key, created_at) VALUES (?, ?)',
      [key, now.toIso8601String()],
    );
    final changes = await txn.rawQuery('SELECT changes() AS count');
    return changes.single['count'] == 1;
  });
}

Future<void> releaseBudgetNotification(Database db, String key) =>
    db.delete('budget_update_log', where: 'delivery_key = ?', whereArgs: [key]);
