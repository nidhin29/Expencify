import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:expencify/domain/repositories/registered_entity_repository.dart';
import 'registered_entity_event.dart';
import 'registered_entity_state.dart';

class RegisteredEntityBloc
    extends Bloc<RegisteredEntityEvent, RegisteredEntityState> {
  final RegisteredEntityRepository _repository;

  RegisteredEntityBloc(this._repository) : super(RegisteredEntityInitial()) {
    on<LoadRegisteredEntities>(_onLoadRegisteredEntities);
    on<AddRegisteredEntity>(_onAddRegisteredEntity);
    on<DeleteRegisteredEntity>(_onDeleteRegisteredEntity);
    on<UpdateRegisteredEntity>(_onUpdateRegisteredEntity);
  }

  Future<void> _onLoadRegisteredEntities(
    LoadRegisteredEntities event,
    Emitter<RegisteredEntityState> emit,
  ) async {
    emit(RegisteredEntityLoading());
    try {
      final entities = await _repository.getAll();
      emit(RegisteredEntityLoaded(entities));
    } catch (e) {
      emit(RegisteredEntityError(e.toString()));
    }
  }

  Future<void> _onAddRegisteredEntity(
    AddRegisteredEntity event,
    Emitter<RegisteredEntityState> emit,
  ) async {
    try {
      await _repository.add(event.entity);
      add(LoadRegisteredEntities());
    } catch (e) {
      emit(RegisteredEntityError(e.toString()));
    }
  }

  Future<void> _onDeleteRegisteredEntity(
    DeleteRegisteredEntity event,
    Emitter<RegisteredEntityState> emit,
  ) async {
    try {
      await _repository.delete(event.id);
      add(LoadRegisteredEntities());
    } catch (e) {
      emit(RegisteredEntityError(e.toString()));
    }
  }

  Future<void> _onUpdateRegisteredEntity(
    UpdateRegisteredEntity event,
    Emitter<RegisteredEntityState> emit,
  ) async {
    try {
      await _repository.update(event.entity);
      add(LoadRegisteredEntities());
    } catch (e) {
      emit(RegisteredEntityError(e.toString()));
    }
  }
}
