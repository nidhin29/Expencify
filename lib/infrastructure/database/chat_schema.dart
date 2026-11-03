import 'package:sqflite/sqflite.dart';

class ChatSchema {
  static Future<void> ensure(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS chat_conversations(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, memory TEXT NOT NULL DEFAULT \'null\')',
    );
    Future<void> column(String table, String name, String definition) async {
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      if (!columns.any((c) => c['name'] == name)) {
        await db.execute('ALTER TABLE $table ADD COLUMN $name $definition');
      }
    }

    // The single pre-existing chat becomes conversation 1, without rewriting it.
    await column(
      'chat_state',
      'active_conversation',
      'INTEGER NOT NULL DEFAULT 1',
    );
    await column(
      'chat_messages',
      'conversation_id',
      'INTEGER NOT NULL DEFAULT 1',
    );
    await column(
      'chat_query_context',
      'conversation_id',
      'INTEGER NOT NULL DEFAULT 1',
    );
    final conversations = await db.query(
      'chat_conversations',
      columns: ['id'],
      limit: 1,
    );
    if (conversations.isEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = await db.insert('chat_conversations', {
        'title': 'New chat',
        'created_at': now,
        'updated_at': now,
      });
      await db.update('chat_state', {'active_conversation': id}, where: 'id=1');
      await db.update('chat_messages', {'conversation_id': id});
      await db.update('chat_query_context', {'conversation_id': id});
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS chat_messages_conversation ON chat_messages(conversation_id,id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS chat_context_conversation ON chat_query_context(conversation_id,id)',
    );
  }

  /// Used by financial reset/restore: no archived conversation may retain data.
  static Future<void> reset(DatabaseExecutor db) async {
    await db.delete('chat_messages');
    await db.delete('chat_query_context');
    await db.delete('chat_conversations');
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert('chat_conversations', {
      'title': 'New chat',
      'created_at': now,
      'updated_at': now,
    });
    await db.rawUpdate(
      'UPDATE chat_state SET generation=generation+1, active_conversation=? WHERE id=1',
      [id],
    );
  }
}
