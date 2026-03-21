import 'package:expencify/domain/entities/registered_entity.dart';
import 'package:expencify/domain/repositories/registered_entity_repository.dart';
import 'package:expencify/infrastructure/database/database_helper.dart';

class SqliteRegisteredEntityRepository implements RegisteredEntityRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  @override
  Future<List<RegisteredEntity>> getAll() async {
    final maps = await _dbHelper.queryAll('registered_entities');
    return maps.map((map) => RegisteredEntity.fromMap(map)).toList();
  }

  @override
  Future<void> add(RegisteredEntity entity) async {
    await _dbHelper.insert('registered_entities', entity.toMap());
  }

  @override
  Future<void> delete(int id) async {
    await _dbHelper.delete('registered_entities', id);
  }

  @override
  Future<void> update(RegisteredEntity entity) async {
    if (entity.id == null) return;
    await _dbHelper.update('registered_entities', entity.toMap(), entity.id!);
  }
}
