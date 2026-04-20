import 'package:equatable/equatable.dart';
import '../../../domain/entities/subscription.dart';

abstract class SubscriptionState extends Equatable {
  const SubscriptionState();

  @override
  List<Object?> get props => [];
}

class SubscriptionInitial extends SubscriptionState {}

class SubscriptionLoading extends SubscriptionState {}

class SubscriptionLoaded extends SubscriptionState {
  final List<SubscriptionModel> subscriptions;
  final List<SubscriptionModel> potentials;

  const SubscriptionLoaded({
    required this.subscriptions,
    this.potentials = const [],
  });

  @override
  List<Object?> get props => [subscriptions, potentials];
}

class SubscriptionError extends SubscriptionState {
  final String message;
  const SubscriptionError(this.message);

  @override
  List<Object?> get props => [message];
}
