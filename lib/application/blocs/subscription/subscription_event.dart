import 'package:equatable/equatable.dart';
import '../../../domain/entities/subscription.dart';

abstract class SubscriptionEvent extends Equatable {
  const SubscriptionEvent();

  @override
  List<Object?> get props => [];
}

class LoadSubscriptions extends SubscriptionEvent {}

class ScanForPotentialSubscriptions extends SubscriptionEvent {}

class AddSubscription extends SubscriptionEvent {
  final SubscriptionModel subscription;
  const AddSubscription(this.subscription);

  @override
  List<Object?> get props => [subscription];
}

class DeleteSubscription extends SubscriptionEvent {
  final int id;
  const DeleteSubscription(this.id);

  @override
  List<Object?> get props => [id];
}

class ToggleSubscriptionStatus extends SubscriptionEvent {
  final SubscriptionModel subscription;
  const ToggleSubscriptionStatus(this.subscription);

  @override
  List<Object?> get props => [subscription];
}
