import '../../../infrastructure/database/database_helper.dart';
import 'package:sqflite/sqflite.dart';

class SmsReviewStore {
  final DatabaseHelper helper;
  SmsReviewStore([DatabaseHelper? helper])
    : helper = helper ?? DatabaseHelper();
  Future<void> add(
    String identity,
    String body,
    String? sender,
    DateTime date,
    String reason,
  ) async {
    final db = await helper.database;
    await db.transaction((txn) async {
      if ((await txn.query(
        'processed_sms_log',
        where: 'body = ?',
        whereArgs: [identity],
        limit: 1,
      )).isNotEmpty) {
        return;
      }
      await txn.insert('sms_review', {
        'identity': identity,
        'body': body,
        'sender': sender ?? '',
        'date': date.toIso8601String(),
        'reason': reason,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }

  Future<List<Map<String, Object?>>> pending() async =>
      (await helper.database).query('sms_review', orderBy: 'date DESC');
  Future<void> dismiss(String identity) async {
    final db = await helper.database;
    await db.transaction((txn) async {
      await txn.insert('processed_sms_log', {
        'body': identity,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.delete(
        'sms_review',
        where: 'identity = ?',
        whereArgs: [identity],
      );
    });
  }
}
