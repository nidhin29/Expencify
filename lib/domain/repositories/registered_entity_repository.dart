import 'package:expencify/domain/entities/registered_entity.dart';

abstract class RegisteredEntityRepository {
  Future<List<RegisteredEntity>> getAll();
  Future<void> add(RegisteredEntity entity);
  Future<void> delete(int id);
  Future<void> update(RegisteredEntity entity);
}
