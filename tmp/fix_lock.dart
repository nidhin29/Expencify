import 'dart:io';

void main() {
  final file = File(
    r'e:\Project_files_1\expencify\lib\application\services\sms\background_sms_handler.dart',
  );
  String content = file.readAsStringSync();

  final regex = RegExp(r'// ── RACE CONDITION GUARD.*?try\s*\{', dotAll: true);

  final replacement =
      '''// ── ATOMIC SQLITE RACE CONDITION GUARD ──────────────────────────────────
  final cleanBody = body.trim().replaceAll(RegExp(r'\\s+'), ' ');
  final nowMs = DateTime.now().millisecondsSinceEpoch;

  final db = await dbHelper.database;

  await db.execute(\'\'\'
    CREATE TABLE IF NOT EXISTS processed_sms_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      body TEXT,
      timestamp INTEGER
    )
  \'\'\');

  await db.execute('DELETE FROM processed_sms_log WHERE timestamp < ?', [nowMs - 60000]);

  final rowsAffected = await db.rawInsert(\'\'\'
    INSERT INTO processed_sms_log (body, timestamp)
    SELECT ?, ? WHERE NOT EXISTS (
      SELECT 1 FROM processed_sms_log 
      WHERE body = ? AND ABS(? - timestamp) < 10000
    )
  \'\'\', [cleanBody, nowMs, cleanBody, nowMs]);

  if (rowsAffected == 0) {
    debugPrint('>>> [EXPENCIFY] Atomic Race Condition Guard Triggered — Duplicate SMS aborted √');
    return;
  }

  try {''';

  if (regex.hasMatch(content)) {
    content = content.replaceAll(regex, replacement);
    file.writeAsStringSync(content);
    print('SUCCESS: Lock updated');
  } else {
    print('ERROR: Regex did not match');
  }
}
