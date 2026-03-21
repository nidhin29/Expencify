import 'package:equatable/equatable.dart';
import '../../../domain/entities/reminder.dart';

abstract class ReminderState extends Equatable {
  const ReminderState();

  @override
  List<Object?> get props => [];
}

class ReminderInitial extends ReminderState {}

class ReminderLoading extends ReminderState {}

class ReminderLoaded extends ReminderState {
  final List<Reminder> reminders;
  const ReminderLoaded(this.reminders);

  @override
  List<Object?> get props => [reminders];
}

class ReminderError extends ReminderState {
  final String message;
  const ReminderError(this.message);

  @override
  List<Object?> get props => [message];
}
