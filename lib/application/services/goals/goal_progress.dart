import '../../../domain/entities/goal.dart';
import '../notifications/budget_update_service.dart';

String goalProgressMessage(Goal before, Goal after) {
  if (!before.isCompleted && after.isCompleted) {
    return '${after.name} reached! ${BudgetUpdateService.amount((after.savedAmount * 100).round())} recorded toward your goal.';
  }
  for (final percent in [75, 50, 25]) {
    if (before.progress < percent / 100 && after.progress >= percent / 100) {
      return '$percent% of ${after.name} reached!';
    }
  }
  final left = ((after.targetAmount - after.savedAmount) * 100).round();
  return left > 0
      ? 'Savings recorded · ${BudgetUpdateService.amount(left)} left for ${after.name}.'
      : 'Savings recorded for ${after.name}.';
}
