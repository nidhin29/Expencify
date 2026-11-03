import '../../../infrastructure/database/database_helper.dart';
import 'chat_plan_constraints.dart';

/// Literal catalog grounding is permission to plan, never a query result. This
/// lets unfamiliar wording about a known merchant reach the validated compiler.
class ChatRecordGrounding {
  static Future<bool> localEntity(
    DatabaseHelper helper,
    String question,
  ) async {
    if (ChatPlanConstraints.metric(question) == null) return false;
    final db = await helper.database;
    for (final (table, field) in [
      ('transactions', 'merchant'),
      ('accounts', 'name'),
      ('categories', 'name'),
    ]) {
      final found = await db.rawQuery(
        'SELECT DISTINCT $field AS name FROM $table WHERE LENGTH($field)>1 AND INSTR(LOWER(?),LOWER($field))>0 LIMIT 16',
        [question],
      );
      if (found.any(
        (r) => RegExp(
          '\\b(?:at|to|from|in|on|for|merchant|category|account)\\s+${RegExp.escape('${r['name']}'.toLowerCase())}(?![a-z0-9])',
        ).hasMatch(question.toLowerCase()),
      )) {
        return true;
      }
    }
    return false;
  }
}
