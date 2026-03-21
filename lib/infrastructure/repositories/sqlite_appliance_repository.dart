import '../../domain/entities/appliance.dart';
import '../../domain/repositories/appliance_repository.dart';
import '../database/database_helper.dart';

class SqliteApplianceRepository implements ApplianceRepository {
  final DatabaseHelper _db;

  SqliteApplianceRepository(this._db);

  @override
  Future<List<Appliance>> getAll() async {
    final rows = await _db.queryAll('appliances');
    return rows.map(Appliance.fromMap).toList();
  }

  @override
  Future<int> save(Appliance appliance) async {
    if (appliance.id != null) {
      return await _db.update('appliances', appliance.toMap(), appliance.id!);
    } else {
      return await _db.insert('appliances', appliance.toMap());
    }
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete('appliances', id);
  }
}
