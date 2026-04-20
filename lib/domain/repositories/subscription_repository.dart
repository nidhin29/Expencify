import '../entities/subscription.dart';

abstract class SubscriptionRepository {
  Future<List<SubscriptionModel>> getAll({bool? activeOnly});
  Future<int> save(SubscriptionModel subscription);
  Future<void> delete(int id);
  Future<List<SubscriptionModel>> findPotentialSubscriptions();
}
