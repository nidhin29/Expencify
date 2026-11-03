import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/repositories/appliance_repository.dart';
import 'appliance_event.dart';
import 'appliance_state.dart';
import '../../services/notifications/notification_service.dart';

class ApplianceBloc extends Bloc<ApplianceEvent, ApplianceState> {
  ApplianceLoaded? _lastLoaded;
  int _loadRevision = 0;
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
    final request = ++_loadRevision;
    final previous = state is ApplianceLoaded
        ? state as ApplianceLoaded
        : _lastLoaded;
    emit(
      previous == null
          ? ApplianceLoading()
          : ApplianceLoaded(previous.appliances, refreshing: true),
    );
    try {
      final appliances = await _repository.getAll();
      if (emit.isDone || request != _loadRevision) return;
      emit(ApplianceLoaded(appliances));
      if (state is ApplianceLoaded) _lastLoaded = state as ApplianceLoaded;
    } catch (e) {
      if (emit.isDone || request != _loadRevision) return;
      emit(
        previous == null
            ? ApplianceError('Could not load appliances. Try again.')
            : ApplianceLoaded(
                previous.appliances,
                refreshError:
                    'Could not refresh. Your previous data is still shown.',
              ),
      );
    }
  }

  Future<void> _onSaveAppliance(
    SaveAppliance event,
    Emitter<ApplianceState> emit,
  ) async {
    try {
      final id = await _repository.save(event.appliance);

      await NotificationService().scheduleApplianceAMC(
        id: event.appliance.id ?? id,
        name: event.appliance.name,
        brand: event.appliance.brand,
        amcExpiryDate: event.appliance.amcExpiryDate,
      );

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
      await NotificationService().cancelApplianceAMC(event.id);
      add(LoadAppliances());
    } catch (e) {
      emit(ApplianceError(e.toString()));
    }
  }
}
