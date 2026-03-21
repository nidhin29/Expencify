import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/repositories/reminder_repository.dart';
import '../../services/notifications/notification_service.dart';
import 'reminder_event.dart';
import 'reminder_state.dart';

class ReminderBloc extends Bloc<ReminderEvent, ReminderState> {
  final ReminderRepository _repository;
  final NotificationService _notificationService;

  ReminderBloc(this._repository, this._notificationService)
    : super(ReminderInitial()) {
    on<LoadReminders>(_onLoadReminders);
    on<SaveReminder>(_onSaveReminder);
    on<DeleteReminder>(_onDeleteReminder);
  }

  Future<void> _onLoadReminders(
    LoadReminders event,
    Emitter<ReminderState> emit,
  ) async {
    emit(ReminderLoading());
    try {
      final reminders = await _repository.getAll();
      emit(ReminderLoaded(reminders));
    } catch (e) {
      emit(ReminderError(e.toString()));
    }
  }

  Future<void> _onSaveReminder(
    SaveReminder event,
    Emitter<ReminderState> emit,
  ) async {
    try {
      final r = event.reminder;
      final id = await _repository.save(r);

      // Handle notification side-effects
      if (r.id != null) {
        await _notificationService.cancelReminder(r.id!);
      }
      await _notificationService.scheduleReminder(
        id: id,
        title: r.title,
        amount: r.amount,
        dueDate: r.dueDate,
      );

      add(LoadReminders());
    } catch (e) {
      emit(ReminderError(e.toString()));
    }
  }

  Future<void> _onDeleteReminder(
    DeleteReminder event,
    Emitter<ReminderState> emit,
  ) async {
    try {
      await _notificationService.cancelReminder(event.id);
      await _repository.delete(event.id);
      add(LoadReminders());
    } catch (e) {
      emit(ReminderError(e.toString()));
    }
  }
}
