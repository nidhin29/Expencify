import '../entities/appliance.dart';

abstract class ApplianceRepository {
  Future<List<Appliance>> getAll();
  Future<int> save(Appliance appliance); // insert or update
  Future<void> delete(int id);
}
