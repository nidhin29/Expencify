import 'package:equatable/equatable.dart';
import '../../../domain/entities/appliance.dart';

abstract class ApplianceState extends Equatable {
  const ApplianceState();

  @override
  List<Object?> get props => [];
}

class ApplianceInitial extends ApplianceState {}

class ApplianceLoading extends ApplianceState {}

class ApplianceLoaded extends ApplianceState {
  final List<Appliance> appliances;
  const ApplianceLoaded(this.appliances);

  @override
  List<Object?> get props => [appliances];
}

class ApplianceError extends ApplianceState {
  final String message;
  const ApplianceError(this.message);

  @override
  List<Object?> get props => [message];
}
