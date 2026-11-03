import 'dart:async';
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

/// Uses the viewed due date to ignore stale/double submissions.
class HandleReminder extends ReminderEvent {
  final Reminder reminder;
  final Completer<HandledReminder?>? completion;
  const HandleReminder(this.reminder, {this.completion});
  @override
  List<Object?> get props => [reminder];
}

class HandledReminder {
  final Reminder original;
  final Reminder? next;
  bool undone = false;
  HandledReminder(this.original, this.next);
}

class UndoHandleReminder extends HandleReminder {
  final HandledReminder result;
  UndoHandleReminder(this.result) : super(result.original);
}
