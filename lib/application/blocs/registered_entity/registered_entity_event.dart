import 'package:equatable/equatable.dart';
import 'package:expencify/domain/entities/registered_entity.dart';

abstract class RegisteredEntityEvent extends Equatable {
  const RegisteredEntityEvent();

  @override
  List<Object?> get props => [];
}

class LoadRegisteredEntities extends RegisteredEntityEvent {}

class AddRegisteredEntity extends RegisteredEntityEvent {
  final RegisteredEntity entity;
  const AddRegisteredEntity(this.entity);

  @override
  List<Object?> get props => [entity];
}

class DeleteRegisteredEntity extends RegisteredEntityEvent {
  final int id;
  const DeleteRegisteredEntity(this.id);

  @override
  List<Object?> get props => [id];
}
