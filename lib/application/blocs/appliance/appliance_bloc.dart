import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/repositories/appliance_repository.dart';
import 'appliance_event.dart';
import 'appliance_state.dart';

class ApplianceBloc extends Bloc<ApplianceEvent, ApplianceState> {
  final ApplianceRepository _repository;

  ApplianceBloc(this._repository) : super(ApplianceInitial()) {
    on<LoadAppliances>(_onLoadAppliances);
    on<SaveAppliance>(_onSaveAppliance);
    on<DeleteAppliance>(_onDeleteAppliance);
  }

  Future<void> _onLoadAppliances(
    LoadAppliances event,
    Emitter<ApplianceState> emit,
  ) async {
    emit(ApplianceLoading());
    try {
      final appliances = await _repository.getAll();
      emit(ApplianceLoaded(appliances));
    } catch (e) {
      emit(ApplianceError(e.toString()));
    }
  }

  Future<void> _onSaveAppliance(
    SaveAppliance event,
    Emitter<ApplianceState> emit,
  ) async {
    try {
      await _repository.save(event.appliance);
      add(LoadAppliances());
    } catch (e) {
      emit(ApplianceError(e.toString()));
    }
  }

  Future<void> _onDeleteAppliance(
    DeleteAppliance event,
    Emitter<ApplianceState> emit,
  ) async {
    try {
      await _repository.delete(event.id);
      add(LoadAppliances());
    } catch (e) {
      emit(ApplianceError(e.toString()));
    }
  }
}
