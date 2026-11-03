import 'dart:convert';
import '../../../infrastructure/database/database_helper.dart';

/// Only a resolved query, not cached financial figures. Stored inside the same
/// encrypted database as chat; excluded from exports and invalidated on clear.
class ChatQueryContextStore {
  final DatabaseHelper helper;
  ChatQueryContextStore(this.helper);
  Future<int> generation() async =>
      (await (await helper.database).query(
            'chat_state',
            where: 'id=1',
          )).single['generation']
          as int;

  Future<Map<String, dynamic>?> load(
    List<Map<String, dynamic>> history,
    int? account,
    int generation,
  ) async {
    if (history.isEmpty) return null;
    final db = await helper.database;
    final state = (await db.query('chat_state', where: 'id=1')).single;
    if (state['generation'] != generation) return null;
    // The UI persists its current user turn before inference. That generation-
    // checked turn binds this request to the active conversation even when the
    // previous query has fallen outside the bounded model transcript.
    final current = history
        .where(
          (m) =>
              m['pending'] == true &&
              m['isUser'] == true &&
              m['chat_generation'] == generation &&
              m['text'] is String,
        )
        .lastOrNull;
    final currentRows = current == null
        ? <Map<String, Object?>>[]
        : await db.query(
            'chat_messages',
            columns: ['id'],
            where:
                'conversation_id=? AND role=? AND text=?${current['id'] is int ? ' AND id=?' : ''}',
            whereArgs: [
              state['active_conversation'],
              'user',
              current['text'],
              if (current['id'] is int) current['id'],
            ],
            orderBy: 'id DESC',
            limit: 1,
          );
    final currentId = currentRows.isEmpty
        ? null
        : currentRows.single['id'] as int;
    final boundToConversation = currentId != null;
    final rows = await db.query(
      'chat_query_context',
      where:
          'conversation_id=? AND ${account == null ? 'account_id IS NULL' : 'account_id=?'}',
      whereArgs: [state['active_conversation'], if (account != null) account],
      orderBy: 'id DESC',
      limit: 120,
    );
    for (final row in rows) {
      // Retrying an older turn must never inherit a later query, even though
      // both belong to the same conversation.
      if (currentId != null &&
          row['question_id'] is int &&
          (row['question_id'] as int) >= currentId) {
        continue;
      }
      final present = history.any(
        (m) =>
            m['isUser'] == true &&
            m['pending'] != true &&
            (row['question_id'] != null && m['id'] != null
                ? row['question_id'] == m['id']
                : row['question'] == m['text']),
      );
      if ((!present && (!boundToConversation || row['question_id'] == null)) ||
          row['plan'] is! String ||
          (row['plan'] as String).length > 6000) {
        continue;
      }
      try {
        final value = jsonDecode(row['plan'] as String);
        if (value is Map<String, dynamic> && value['queries'] is List) {
          return value;
        }
      } on FormatException {
        /* Ignore invalid context; never treat it as a query. */
      }
    }
    return null;
  }

  Future<void> save(
    String question,
    Map<String, dynamic> plan,
    int? account,
    int expectedGeneration,
  ) async {
    final encoded = jsonEncode(plan);
    if (encoded.length > 6000) return;
    await (await helper.database).transaction((txn) async {
      final state = (await txn.query('chat_state', where: 'id=1')).single;
      final current = state['generation'];
      final conversation = state['active_conversation'];
      if (current != expectedGeneration) return;
      final messages = await txn.query(
        'chat_messages',
        columns: ['id'],
        where: 'role=? AND text=? AND conversation_id=?',
        whereArgs: ['user', question, conversation],
        orderBy: 'id DESC',
        limit: 1,
      );
      await txn.insert('chat_query_context', {
        'generation': current,
        'conversation_id': conversation,
        'account_id': account,
        'question': question,
        'question_id': messages.isEmpty ? null : messages.single['id'],
        'plan': encoded,
      });
      await txn.rawDelete(
        'DELETE FROM chat_query_context WHERE conversation_id=? AND id NOT IN (SELECT id FROM chat_query_context WHERE conversation_id=? ORDER BY id DESC LIMIT 120)',
        [conversation, conversation],
      );
    });
  }
}
