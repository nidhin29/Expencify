import 'package:sqflite/sqflite.dart';
import 'chat_memory.dart';
import '../../../infrastructure/database/database_helper.dart';

class ChatMessage {
  final int? id;
  final String text;
  final bool isUser, failed;
  final String? prompt;
  const ChatMessage({
    this.id,
    required this.text,
    required this.isUser,
    this.failed = false,
    this.prompt,
  });
  Map<String, Object?> toMap() => {
    'text': text,
    'role': isUser ? 'user' : 'assistant',
    'failed': failed ? 1 : 0,
    'prompt': prompt,
  };
  Map<String, dynamic> toHistory() => {
    'text': text,
    'isUser': isUser,
    if (id != null) 'id': id,
    if (failed) 'failed': true,
  };
  ChatMessage withId(int value) => ChatMessage(
    id: value,
    text: text,
    isUser: isUser,
    failed: failed,
    prompt: prompt,
  );
  factory ChatMessage.fromMap(Map<String, Object?> row) => ChatMessage(
    id: row['id'] as int,
    text: row['text'] as String,
    isUser: row['role'] == 'user',
    failed: row['failed'] == 1,
    prompt: row['prompt'] as String?,
  );
}

/// Conversation history shares SQLCipher protection with financial records.
/// It is deliberately excluded from transferable backup snapshots.
class ChatHistoryCleared implements Exception {}

class ChatPage {
  final List<ChatMessage> messages;
  final bool hasEarlier;
  const ChatPage(this.messages, this.hasEarlier);
}

class ChatSnapshot extends ChatPage {
  final int generation;
  final List<Map<String, dynamic>> memory;
  const ChatSnapshot(
    this.generation,
    super.messages,
    super.hasEarlier,
    this.memory,
  );
}

class ChatConversationInfo {
  final int id, count;
  final String title;
  final DateTime updated;
  final bool active;
  const ChatConversationInfo(
    this.id,
    this.title,
    this.updated,
    this.count,
    this.active,
  );
}

class ChatHistoryStore {
  final DatabaseHelper helper;
  ChatHistoryStore([DatabaseHelper? helper])
    : helper = helper ?? DatabaseHelper();
  Future<int> generation() async =>
      (await (await helper.database).query(
            'chat_state',
            where: 'id=1',
          )).single['generation']
          as int;

  Future<Map<String, Object?>> _conversation(
    DatabaseExecutor db,
    int id,
  ) async {
    var row = (await db.query(
      'chat_conversations',
      where: 'id=?',
      whereArgs: [id],
    )).single;
    if (row['memory'] == 'null') {
      var memory = '[]';
      final users = await db.query(
        'chat_messages',
        where: 'conversation_id=? AND role=?',
        whereArgs: [id, 'user'],
        orderBy: 'id',
      );
      for (final m in users) {
        memory = ChatMemory.update(memory, m['text'] as String, m['id'] as int);
      }
      final values = <String, Object?>{'memory': memory};
      if (row['title'] == 'New chat' && users.isNotEmpty) {
        values['title'] = _title(users.first['text'] as String);
      }
      await db.update(
        'chat_conversations',
        values,
        where: 'id=?',
        whereArgs: [id],
      );
      row = {...row, ...values};
    }
    return row;
  }

  static String _title(String text) {
    final value = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return value.length > 70 ? value.substring(0, 70) : value;
  }

  Future<ChatPage> _page(
    DatabaseExecutor db,
    int conversation, {
    int? beforeId,
  }) async {
    final rows = await db.query(
      'chat_messages',
      where: 'conversation_id=?${beforeId == null ? '' : ' AND id<?'}',
      whereArgs: [conversation, if (beforeId != null) beforeId],
      orderBy: 'id DESC',
      limit: 120,
    );
    final messages = rows.reversed.map(ChatMessage.fromMap).toList();
    final earlier =
        messages.isNotEmpty &&
        (await db.query(
          'chat_messages',
          columns: ['id'],
          where: 'conversation_id=? AND id<?',
          whereArgs: [conversation, messages.first.id],
          limit: 1,
        )).isNotEmpty;
    return ChatPage(messages, earlier);
  }

  Future<ChatSnapshot> snapshot() async =>
      (await helper.database).transaction((txn) async {
        final state = (await txn.query('chat_state', where: 'id=1')).single;
        final id = state['active_conversation'] as int;
        final row = await _conversation(txn, id);
        final page = await _page(txn, id);
        return ChatSnapshot(
          state['generation'] as int,
          page.messages,
          page.hasEarlier,
          ChatMemory.history(row['memory'] as String),
        );
      });
  Future<List<Map<String, dynamic>>> memory({required int generation}) async =>
      (await helper.database).transaction((txn) async {
        final state = (await txn.query('chat_state', where: 'id=1')).single;
        if (state['generation'] != generation) throw ChatHistoryCleared();
        final row = await _conversation(
          txn,
          state['active_conversation'] as int,
        );
        return ChatMemory.history(row['memory'] as String);
      });
  Future<List<ChatMessage>> load() async => (await snapshot()).messages;
  Future<ChatPage> older(int beforeId, {required int generation}) async =>
      (await helper.database).transaction((txn) async {
        final state = (await txn.query('chat_state', where: 'id=1')).single;
        if (state['generation'] != generation) throw ChatHistoryCleared();
        return _page(
          txn,
          state['active_conversation'] as int,
          beforeId: beforeId,
        );
      });
  Future<List<ChatConversationInfo>> conversations() async {
    final rows = await (await helper.database).rawQuery(
      'SELECT c.*, COUNT(m.id) AS count, c.id=s.active_conversation AS active FROM chat_conversations c CROSS JOIN chat_state s LEFT JOIN chat_messages m ON m.conversation_id=c.id WHERE s.id=1 GROUP BY c.id ORDER BY c.updated_at DESC,c.id DESC',
    );
    return rows
        .map(
          (r) => ChatConversationInfo(
            r['id'] as int,
            r['title'] as String,
            DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
            r['count'] as int,
            r['active'] == 1,
          ),
        )
        .toList();
  }

  Future<int> newConversation({
    int? generation,
  }) async => (await helper.database).transaction((txn) async {
    final state = (await txn.query('chat_state', where: 'id=1')).single;
    if (generation != null && generation != state['generation']) {
      throw ChatHistoryCleared();
    }
    final current = state['active_conversation'] as int;
    if ((await txn.query(
      'chat_messages',
      columns: ['id'],
      where: 'conversation_id=?',
      whereArgs: [current],
      limit: 1,
    )).isEmpty) {
      return state['generation'] as int;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await txn.insert('chat_conversations', {
      'title': 'New chat',
      'created_at': now,
      'updated_at': now,
      'memory': '[]',
    });
    await txn.rawUpdate(
      'UPDATE chat_state SET active_conversation=?, generation=generation+1 WHERE id=1',
      [id],
    );
    return (state['generation'] as int) + 1;
  });
  Future<void> activate(
    int id, {
    required int generation,
  }) async => (await helper.database).transaction((txn) async {
    final state = (await txn.query('chat_state', where: 'id=1')).single;
    if (generation != state['generation']) throw ChatHistoryCleared();
    if ((await txn.query(
      'chat_conversations',
      columns: ['id'],
      where: 'id=?',
      whereArgs: [id],
    )).isEmpty) {
      throw ChatHistoryCleared();
    }
    if (state['active_conversation'] != id) {
      await txn.rawUpdate(
        'UPDATE chat_state SET active_conversation=?, generation=generation+1 WHERE id=1',
        [id],
      );
    }
  });

  Future<ChatMessage> save(ChatMessage message, {int? generation}) async {
    final db = await helper.database;
    return db.transaction((txn) async {
      final state = (await txn.query('chat_state', where: 'id=1')).single;
      if (generation != null && state['generation'] != generation) {
        throw ChatHistoryCleared();
      }
      final conversation = state['active_conversation'] as int;
      var id = message.id;
      final values = {...message.toMap(), 'conversation_id': conversation};
      if (id == null) {
        id = await txn.insert('chat_messages', values);
      } else {
        final changed = await txn.update(
          'chat_messages',
          values,
          where: 'id=? AND conversation_id=?',
          whereArgs: [id, conversation],
        );
        if (changed != 1) throw ChatHistoryCleared();
      }
      final row = await _conversation(txn, conversation);
      final updated = <String, Object?>{
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };
      if (message.isUser) {
        updated['memory'] = ChatMemory.update(
          row['memory'] as String,
          message.text,
          id,
        );
        if (row['title'] == 'New chat') updated['title'] = _title(message.text);
      }
      await txn.update(
        'chat_conversations',
        updated,
        where: 'id=?',
        whereArgs: [conversation],
      );
      // Older messages stay available for scrolling and archived conversations.
      return message.withId(id);
    });
  }

  Future<void> clear() async =>
      (await helper.database).transaction((txn) async {
        final state = (await txn.query('chat_state', where: 'id=1')).single;
        final id = state['active_conversation'] as int;
        await txn.delete(
          'chat_messages',
          where: 'conversation_id=?',
          whereArgs: [id],
        );
        await txn.delete(
          'chat_query_context',
          where: 'conversation_id=?',
          whereArgs: [id],
        );
        await txn.update(
          'chat_conversations',
          {
            'title': 'New chat',
            'memory': '[]',
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id=?',
          whereArgs: [id],
        );
        await txn.rawUpdate(
          'UPDATE chat_state SET generation=generation+1 WHERE id=1',
        );
      });
}
