import 'package:equatable/equatable.dart';
import 'package:expencify/domain/entities/registered_entity.dart';

abstract class RegisteredEntityState extends Equatable {
  const RegisteredEntityState();

  @override
  List<Object?> get props => [];
}

class RegisteredEntityInitial extends RegisteredEntityState {}

class RegisteredEntityLoading extends RegisteredEntityState {}

class RegisteredEntityLoaded extends RegisteredEntityState {
  final List<RegisteredEntity> entities;
  const RegisteredEntityLoaded(this.entities);

  @override
  List<Object?> get props => [entities];
}

class RegisteredEntityError extends RegisteredEntityState {
  final String message;
  const RegisteredEntityError(this.message);

  @override
  List<Object?> get props => [message];
}
