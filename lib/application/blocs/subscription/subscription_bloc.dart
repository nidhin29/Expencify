import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/repositories/subscription_repository.dart';
import '../../services/notifications/notification_service.dart';
import 'subscription_event.dart';
import 'subscription_state.dart';

class SubscriptionBloc extends Bloc<SubscriptionEvent, SubscriptionState> {
  SubscriptionLoaded? _lastLoaded;
  int _loadRevision = 0;
  final SubscriptionRepository _repository;
  final NotificationService _notifications;

  SubscriptionBloc(this._repository, this._notifications)
    : super(SubscriptionInitial()) {
    on<LoadSubscriptions>(_onLoadSubscriptions);
    on<ScanForPotentialSubscriptions>(_onScanPotentials);
    on<AddSubscription>(_onAddSubscription);
    on<DeleteSubscription>(_onDeleteSubscription);
    on<ToggleSubscriptionStatus>(_onToggleStatus);
  }

  Future<void> _onLoadSubscriptions(
    LoadSubscriptions event,
    Emitter<SubscriptionState> emit,
  ) async {
    final request = ++_loadRevision;
    final previous = state is SubscriptionLoaded
        ? state as SubscriptionLoaded
        : _lastLoaded;
    emit(
      previous == null
          ? SubscriptionLoading()
          : SubscriptionLoaded(
              subscriptions: previous.subscriptions,
              potentials: previous.potentials,
              refreshing: true,
            ),
    );
    try {
      final subs = await _repository.getAll();

      // Startup and subscription mutations schedule notifications separately.
      if (emit.isDone || request != _loadRevision) return;
      emit(SubscriptionLoaded(subscriptions: subs));
      if (state is SubscriptionLoaded) {
        _lastLoaded = state as SubscriptionLoaded;
      }
    } catch (e) {
      if (emit.isDone || request != _loadRevision) return;
      emit(
        previous == null
            ? SubscriptionError('Could not load subscriptions. Try again.')
            : SubscriptionLoaded(
                subscriptions: previous.subscriptions,
                potentials: previous.potentials,
                refreshError:
                    'Could not refresh. Your previous data is still shown.',
              ),
      );
    }
  }

  Future<void> _onScanPotentials(
    ScanForPotentialSubscriptions event,
    Emitter<SubscriptionState> emit,
  ) async {
    final currentState = state;
    if (currentState is SubscriptionLoaded) {
      try {
        final potentials = await _repository.findPotentialSubscriptions();
        emit(
          SubscriptionLoaded(
            subscriptions: currentState.subscriptions,
            potentials: potentials,
          ),
        );
      } catch (e) {
        emit(SubscriptionError(e.toString()));
      }
    }
  }

  Future<void> _onAddSubscription(
    AddSubscription event,
    Emitter<SubscriptionState> emit,
  ) async {
    var persisted = false;
    try {
      final id = await _repository.save(event.subscription);
      persisted = true;

      // Schedule reminder
      try {
        await _notifications.scheduleSubscriptionReminder(
          id: id,
          name: event.subscription.name,
          amount: event.subscription.amount,
          nextDueDate: event.subscription.nextDueDate,
          frequency: event.subscription.frequency,
        );
      } catch (_) {
        /* Retry on next launch; the subscription is already saved. */
      }

      add(LoadSubscriptions());
    } catch (e) {
      emit(SubscriptionError(e.toString()));
    } finally {
      final completion = event.completion;
      if (completion != null && !completion.isCompleted) {
        completion.complete(persisted);
      }
    }
  }

  Future<void> _onDeleteSubscription(
    DeleteSubscription event,
    Emitter<SubscriptionState> emit,
  ) async {
    try {
      await _repository.delete(event.id);
      await _notifications.cancelSubscriptionReminder(event.id);
      add(LoadSubscriptions());
    } catch (e) {
      emit(SubscriptionError(e.toString()));
    }
  }

  Future<void> _onToggleStatus(
    ToggleSubscriptionStatus event,
    Emitter<SubscriptionState> emit,
  ) async {
    try {
      final updated = event.subscription.copyWith(
        isActive: !event.subscription.isActive,
      );
      await _repository.save(updated);
      if (!updated.isActive && updated.id != null) {
        await _notifications.cancelSubscriptionReminder(updated.id!);
      } else if (updated.isActive && updated.id != null) {
        await _notifications.scheduleSubscriptionReminder(
          id: updated.id!,
          name: updated.name,
          amount: updated.amount,
          nextDueDate: updated.nextDueDate,
          frequency: updated.frequency,
        );
      }
      add(LoadSubscriptions());
    } catch (e) {
      emit(SubscriptionError(e.toString()));
    }
  }
}
