import '../refresh_status.dart';
import 'package:equatable/equatable.dart';
import 'package:expencify/domain/entities/registered_entity.dart';

abstract class RegisteredEntityState extends Equatable {
  const RegisteredEntityState();

  @override
  List<Object?> get props => [];
}

class RegisteredEntityInitial extends RegisteredEntityState {}

class RegisteredEntityLoading extends RegisteredEntityState {}

class RegisteredEntityLoaded extends RegisteredEntityState
    implements RefreshStatus {
  @override
  final bool refreshing;
  @override
  final String? refreshError;
  final List<RegisteredEntity> entities;
  const RegisteredEntityLoaded(
    this.entities, {
    this.refreshing = false,
    this.refreshError,
  });

  @override
  List<Object?> get props => [refreshing, refreshError, entities];
}

class RegisteredEntityError extends RegisteredEntityState {
  final String message;
  const RegisteredEntityError(this.message);

  @override
  List<Object?> get props => [message];
}
