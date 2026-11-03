import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:expencify/domain/repositories/registered_entity_repository.dart';
import 'registered_entity_event.dart';
import 'registered_entity_state.dart';

class RegisteredEntityBloc
    extends Bloc<RegisteredEntityEvent, RegisteredEntityState> {
  RegisteredEntityLoaded? _lastLoaded;
  int _loadRevision = 0;
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
    final request = ++_loadRevision;
    final previous = state is RegisteredEntityLoaded
        ? state as RegisteredEntityLoaded
        : _lastLoaded;
    emit(
      previous == null
          ? RegisteredEntityLoading()
          : RegisteredEntityLoaded(previous.entities, refreshing: true),
    );
    try {
      final entities = await _repository.getAll();
      if (emit.isDone || request != _loadRevision) return;
      _lastLoaded = RegisteredEntityLoaded(entities);
      emit(_lastLoaded!);
    } catch (e) {
      if (emit.isDone || request != _loadRevision) return;
      emit(
        previous == null
            ? const RegisteredEntityError('Could not load saved merchants.')
            : RegisteredEntityLoaded(
                previous.entities,
                refreshError:
                    'Could not refresh. Your previous data is still shown.',
              ),
      );
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
