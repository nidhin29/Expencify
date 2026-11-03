import '../refresh_status.dart';
import 'package:equatable/equatable.dart';
import '../../../domain/entities/reminder.dart';

abstract class ReminderState extends Equatable {
  const ReminderState();

  @override
  List<Object?> get props => [];
}

class ReminderInitial extends ReminderState {}

class ReminderLoading extends ReminderState {}

class ReminderLoaded extends ReminderState implements RefreshStatus {
  @override
  final bool refreshing;
  @override
  final String? refreshError;
  final List<Reminder> reminders;
  const ReminderLoaded(
    this.reminders, {
    this.refreshing = false,
    this.refreshError,
  });

  @override
  List<Object?> get props => [refreshing, refreshError, reminders];
}

class ReminderError extends ReminderState {
  final String message;
  const ReminderError(this.message);

  @override
  List<Object?> get props => [message];
}
