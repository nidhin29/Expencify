import 'package:equatable/equatable.dart';
import '../../../domain/entities/reminder.dart';

abstract class ReminderEvent extends Equatable {
  const ReminderEvent();

  @override
  List<Object?> get props => [];
}

class LoadReminders extends ReminderEvent {}

class SaveReminder extends ReminderEvent {
  final Reminder reminder;
  const SaveReminder(this.reminder);

  @override
  List<Object?> get props => [reminder];
}

class DeleteReminder extends ReminderEvent {
  final int id;
  const DeleteReminder(this.id);

  @override
  List<Object?> get props => [id];
}
