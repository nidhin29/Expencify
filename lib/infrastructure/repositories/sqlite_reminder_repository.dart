import '../../domain/entities/reminder.dart';
import '../../domain/repositories/reminder_repository.dart';
import '../database/database_helper.dart';

class SqliteReminderRepository implements ReminderRepository {
  final DatabaseHelper _db;

  SqliteReminderRepository(this._db);

  @override
  Future<List<Reminder>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('reminders', orderBy: 'due_date ASC');
    return rows.map(Reminder.fromMap).toList();
  }

  @override
  Future<int> save(Reminder reminder) async {
    if (reminder.id != null) {
      return await _db.update('reminders', reminder.toMap(), reminder.id!);
    } else {
      return await _db.insert('reminders', reminder.toMap());
    }
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete('reminders', id);
  }
}
