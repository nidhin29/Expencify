import '../entities/reminder.dart';

abstract class ReminderRepository {
  Future<List<Reminder>> getAll();
  Future<int> save(Reminder reminder); // insert or update
  Future<void> delete(int id);
}
