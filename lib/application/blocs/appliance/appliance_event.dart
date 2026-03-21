import 'package:equatable/equatable.dart';
import '../../../domain/entities/appliance.dart';

abstract class ApplianceEvent extends Equatable {
  const ApplianceEvent();

  @override
  List<Object?> get props => [];
}

class LoadAppliances extends ApplianceEvent {}

class SaveAppliance extends ApplianceEvent {
  final Appliance appliance;
  const SaveAppliance(this.appliance);

  @override
  List<Object?> get props => [appliance];
}

class DeleteAppliance extends ApplianceEvent {
  final int id;
  const DeleteAppliance(this.id);

  @override
  List<Object?> get props => [id];
}
