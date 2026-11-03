import '../../../domain/entities/reminder.dart';
import '../../services/notifications/recurrence.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/repositories/reminder_repository.dart';
import '../../services/notifications/notification_service.dart';
import 'reminder_event.dart';
import 'reminder_state.dart';

class ReminderBloc extends Bloc<ReminderEvent, ReminderState> {
  ReminderLoaded? _lastLoaded;
  int _loadRevision = 0;
  final ReminderRepository _repository;
  final NotificationService _notificationService;

  ReminderBloc(this._repository, this._notificationService)
    : super(ReminderInitial()) {
    on<HandleReminder>(
      _onHandleReminder,
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
    on<LoadReminders>(_onLoadReminders);
    on<SaveReminder>(_onSaveReminder);
    on<DeleteReminder>(_onDeleteReminder);
  }

  Future<void> _onHandleReminder(
    HandleReminder event,
    Emitter<ReminderState> emit,
  ) async {
    HandledReminder? result;
    try {
      final current = await _repository.getAll();
      if (event is UndoHandleReminder) {
        final previous = event.result;
        if (previous.undone) return;
        final existing = current.where((r) => r.id == previous.original.id);
        if (previous.next == null
            ? existing.isNotEmpty
            : existing.isEmpty || existing.first != previous.next) {
          return;
        }
        final old = previous.original;
        final restored = Reminder(
          id: previous.next == null ? null : old.id,
          title: old.title,
          amount: old.amount,
          dueDate: old.dueDate,
          isRecurring: old.isRecurring,
          frequency: old.frequency,
          recurrenceAnchor: old.recurrenceAnchor,
        );
        final id = await _repository.save(restored);
        previous.undone = true;
        emit(ReminderLoaded(await _repository.getAll()));
        try {
          await _notificationService.scheduleReminder(
            id: id,
            title: old.title,
            amount: old.amount,
            dueDate: old.dueDate,
            frequency: old.isRecurring ? old.frequency : null,
            recurrenceAnchor: old.recurrenceAnchor,
          );
        } catch (_) {
          /* Retry on launch. */
        }
        return;
      }
      final matches = current.where(
        (r) => r.id == event.reminder.id && r.dueDate == event.reminder.dueDate,
      );
      if (matches.isEmpty) return;
      final r = matches.first;
      if (r.isRecurring) {
        final now = DateTime.now();
        final anchor = r.recurrenceAnchor ?? r.dueDate;
        final after = r.dueDate.isAfter(now) ? r.dueDate : now;
        final next = upcomingOccurrences(
          anchor,
          r.frequency,
          after,
          count: 1,
        ).single;
        final updated = Reminder(
          id: r.id,
          title: r.title,
          amount: r.amount,
          dueDate: next,
          isRecurring: true,
          frequency: r.frequency,
          recurrenceAnchor: anchor,
        );
        await _repository.save(updated);
        result = HandledReminder(r, updated);
        emit(ReminderLoaded(await _repository.getAll()));
        try {
          await _notificationService.scheduleReminder(
            id: r.id!,
            title: r.title,
            amount: r.amount,
            dueDate: next,
            frequency: r.frequency,
            recurrenceAnchor: anchor,
          );
        } catch (_) {
          /* Retry notification scheduling on launch. */
        }
      } else {
        await _repository.delete(r.id!);
        result = HandledReminder(r, null);
        emit(ReminderLoaded(await _repository.getAll()));
        try {
          await _notificationService.cancelReminder(r.id!);
        } catch (_) {
          /* Refresh scheduled notifications on launch. */
        }
      }
    } catch (_) {
      emit(
        const ReminderError(
          'Could not update this reminder. Please try again.',
        ),
      );
    } finally {
      final completion = event.completion;
      if (completion != null && !completion.isCompleted) {
        completion.complete(result);
      }
    }
  }

  Future<void> _onLoadReminders(
    LoadReminders event,
    Emitter<ReminderState> emit,
  ) async {
    final request = ++_loadRevision;
    final previous = state is ReminderLoaded
        ? state as ReminderLoaded
        : _lastLoaded;
    emit(
      previous == null
          ? ReminderLoading()
          : ReminderLoaded(previous.reminders, refreshing: true),
    );
    try {
      final reminders = await _repository.getAll();
      if (emit.isDone || request != _loadRevision) return;
      emit(ReminderLoaded(reminders));
      if (state is ReminderLoaded) _lastLoaded = state as ReminderLoaded;
    } catch (e) {
      if (emit.isDone || request != _loadRevision) return;
      emit(
        previous == null
            ? ReminderError('Could not load reminders. Try again.')
            : ReminderLoaded(
                previous.reminders,
                refreshError:
                    'Could not refresh. Your previous data is still shown.',
              ),
      );
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
      await _notificationService.scheduleReminder(
        id: id,
        title: r.title,
        amount: r.amount,
        dueDate: r.dueDate,
        frequency: r.isRecurring ? r.frequency : null,
        recurrenceAnchor: r.recurrenceAnchor,
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
      await _repository.delete(event.id);
      await _notificationService.cancelReminder(event.id);
      add(LoadReminders());
    } catch (e) {
      emit(ReminderError(e.toString()));
    }
  }
}
