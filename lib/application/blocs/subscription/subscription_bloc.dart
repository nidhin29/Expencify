import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/repositories/subscription_repository.dart';
import '../../services/notifications/notification_service.dart';
import 'subscription_event.dart';
import 'subscription_state.dart';

class SubscriptionBloc extends Bloc<SubscriptionEvent, SubscriptionState> {
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
    emit(SubscriptionLoading());
    try {
      final subs = await _repository.getAll();
      
      // Reschedule reminders for all active subs on load to ensure local state sync
      for (final s in subs) {
        if (s.isActive && s.id != null) {
          _notifications.scheduleSubscriptionReminder(
            id: s.id!,
            name: s.name,
            amount: s.amount,
            nextDueDate: s.nextDueDate,
          );
        }
      }

      emit(SubscriptionLoaded(subscriptions: subs));
    } catch (e) {
      emit(SubscriptionError(e.toString()));
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
        emit(SubscriptionLoaded(
          subscriptions: currentState.subscriptions,
          potentials: potentials,
        ));
      } catch (e) {
        emit(SubscriptionError(e.toString()));
      }
    }
  }

  Future<void> _onAddSubscription(
    AddSubscription event,
    Emitter<SubscriptionState> emit,
  ) async {
    try {
      final id = await _repository.save(event.subscription);
      
      // Schedule reminder
      _notifications.scheduleSubscriptionReminder(
        id: id,
        name: event.subscription.name,
        amount: event.subscription.amount,
        nextDueDate: event.subscription.nextDueDate,
      );

      add(LoadSubscriptions());
    } catch (e) {
      emit(SubscriptionError(e.toString()));
    }
  }

  Future<void> _onDeleteSubscription(
    DeleteSubscription event,
    Emitter<SubscriptionState> emit,
  ) async {
    try {
      await _repository.delete(event.id);
      _notifications.cancelSubscriptionReminder(event.id);
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
      final updated = event.subscription.copyWith(isActive: !event.subscription.isActive);
      await _repository.save(updated);
      add(LoadSubscriptions());
    } catch (e) {
      emit(SubscriptionError(e.toString()));
    }
  }
}
