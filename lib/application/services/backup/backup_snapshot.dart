import '../../../infrastructure/database/chat_schema.dart';
import '../security/receipt_store.dart';
import '../performance/performance_probe.dart';
import '../../../domain/entities/subscription.dart';
import '../../../domain/entities/registered_entity.dart';
import '../../../domain/entities/appliance.dart';
import '../../../domain/entities/reminder.dart';
import '../../../domain/entities/goal.dart';
import '../../../domain/entities/budget.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/entities/account.dart';
import 'package:flutter/foundation.dart' show compute, Uint8List;
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../../../infrastructure/database/database_helper.dart';
import '../notifications/notification_service.dart';
import '../security/backup_cipher.dart';
import 'backup_progress.dart';
import 'backup_restore_exception.dart';

/// Snapshots include WAL commits. Restore commits through the live database
/// connection so other isolates cannot keep writing into a replaced file.
class BackupSnapshot {
  static const maxBytes = 50 * 1024 * 1024;
  static const tables = [...DatabaseHelper.financialTables, 'user_settings'];
  final DatabaseHelper helper;
  final String? documentsPath;
  final ReceiptStore receipts;
  final Future<void> Function()? reschedule;
  BackupSnapshot([
    DatabaseHelper? helper,
    this.documentsPath,
    ReceiptStore? receipts,
    this.reschedule,
  ]) : helper = helper ?? DatabaseHelper(),
       receipts = receipts ?? ReceiptStore();

  Future<Uint8List> create(
    String password, {
    BackupProgressCallback? onProgress,
  }) => PerformanceProbe.measure(
    'backup.create',
    () => _create(password, onProgress),
  );

  Future<Uint8List> _create(
    String password,
    BackupProgressCallback? onProgress,
  ) async {
    if (password.length < 12) {
      throw ArgumentError('Use a backup passphrase of at least 12 characters.');
    }
    final db = await helper.database;
    reportBackupProgress(onProgress, BackupStage.readingData);
    final data = <String, List<Map<String, Object?>>>{};
    final images = <String, Uint8List>{};
    await db.transaction((txn) async {
      for (final table in tables) {
        data[table] = (await txn.query(
          table,
        )).map((row) => Map<String, Object?>.from(row)).toList();
        if (table == 'user_settings') {
          for (final row in data[table]!) {
            row['pin'] = null;
            row['auth_token'] = null;
          }
        }
      }
    });
    // Keep receipt I/O and CPU work outside the consistent database snapshot.
    final rows = data['transactions']!;
    final withImages = rows
        .where((row) => row['image_path'] != null && row['image_path'] != '')
        .toList();
    var receiptBytes = 0;
    reportBackupProgress(
      onProgress,
      BackupStage.collectingReceipts,
      completed: 0,
      total: withImages.length,
    );
    for (var index = 0; index < withImages.length; index++) {
      final row = withImages[index];
      final image = row['image_path'] as String;
      final file = File(image);
      if (await file.exists() && await file.length() > 0) {
        if (await file.length() > maxBytes) {
          throw const FormatException('Receipt exceeds backup limit.');
        }
        final key = '${row['id']}.receipt';
        final plain = await receipts.read(image);
        receiptBytes += ((plain.length + 2) ~/ 3) * 4;
        if (receiptBytes > maxBytes) {
          throw StateError('Backup exceeds the 50 MB limit.');
        }
        images[key] = plain;
        row['image_path'] = key;
      } else {
        row['image_path'] = null;
      }
      reportBackupProgress(
        onProgress,
        BackupStage.collectingReceipts,
        completed: index + 1,
        total: withImages.length,
      );
    }
    reportBackupProgress(onProgress, BackupStage.encoding);
    final bytes = await PerformanceProbe.measure(
      'backup.encode',
      () => compute(_encodeSnapshot, (data, images)),
    );
    for (final bytes in images.values) {
      bytes.fillRange(0, bytes.length, 0);
    }
    images.clear();
    data.clear();
    reportBackupProgress(onProgress, BackupStage.encrypting);
    return PerformanceProbe.measure(
      'backup.encrypt',
      () => BackupCipher().encrypt(bytes, password),
    );
  }

  Future<void> restore(
    Uint8List bytes,
    String password, {
    BackupProgressCallback? onProgress,
  }) async {
    var stage = BackupStage.validating;
    try {
      await PerformanceProbe.measure(
        'backup.restore',
        () => _restore(bytes, password, (progress) {
          stage = progress.stage;
          try {
            onProgress?.call(progress);
          } catch (_) {
            // A progress observer must never interrupt an atomic restore.
          }
        }),
      );
    } on BackupRestoreException {
      rethrow;
    } on FormatException {
      rethrow;
    } catch (error, stack) {
      // Fixed categories only: SQL exceptions may contain private record values.
      final category = error is DatabaseException
          ? 'database'
          : error is FileSystemException
          ? 'storage'
          : error is ArgumentError
          ? 'argument'
          : error is StateError
          ? 'state'
          : 'operation';
      final kind = error.runtimeType.toString();
      final safeKind = RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,63}$').hasMatch(kind)
          ? kind
          : 'UnknownError';
      final location = RegExp(
        r'package:expencify/application/services/backup/backup_snapshot\.dart:(\d+)',
      ).firstMatch(stack.toString())?.group(1);
      final sqliteCode = error is DatabaseException
          ? error.getResultCode()
          : null;
      throw BackupRestoreException(
        'Restore stopped while ${BackupProgress(stage).label.replaceAll('…', '').toLowerCase()}. '
        'Error code: ${stage.name}-$category-$safeKind'
        '${sqliteCode == null ? '' : '-sql$sqliteCode'}'
        '${location == null ? '' : '-L$location'}. Your current data was not replaced.',
      );
    }
  }

  Future<void> _restore(
    Uint8List bytes,
    String password,
    BackupProgressCallback? onProgress,
  ) async {
    if (bytes.isEmpty || bytes.length > maxBytes + 1024) {
      throw const FormatException('Invalid backup size.');
    }
    var plain = bytes;
    if (!isPlaintextDatabase(plain)) {
      try {
        reportBackupProgress(onProgress, BackupStage.decrypting);
        plain = await PerformanceProbe.measure(
          'backup.decrypt',
          () => BackupCipher().decrypt(bytes, password),
        );
      } catch (_) {
        throw const BackupRestoreException(
          'Could not unlock this backup. Use its backup passphrase, or the PIN used when an older encrypted backup was created. The file may also be damaged or unsupported.',
        );
      }
    }
    reportBackupProgress(onProgress, BackupStage.validating);
    final Object? decoded;
    if (isPlaintextDatabase(plain)) {
      decoded = await _legacy(plain);
    } else {
      try {
        decoded = await compute(_decodeSnapshot, plain);
      } on FormatException {
        throw const BackupRestoreException(
          'The unlocked backup is not a readable Spendy snapshot. Your current data was not replaced.',
        );
      }
    }
    if (!identical(plain, bytes)) plain.fillRange(0, plain.length, 0);
    plain = Uint8List(0);
    if (decoded is! Map ||
        decoded['format'] != 'spendy' ||
        decoded['version'] != 1 ||
        decoded['tables'] is! Map ||
        decoded['images'] is! Map) {
      throw const BackupRestoreException(
        'This backup uses an unsupported snapshot format or version. Your current data was not replaced.',
      );
    }
    final data = decoded['tables'] as Map;
    final images = decoded['images'] as Map;
    for (final table in tables) {
      if (data[table] is! List ||
          (data[table] as List).any((row) => row is! Map)) {
        throw BackupRestoreException(
          'The backup has a missing or invalid $table table. Your current data was not replaced.',
        );
      }
    }
    final db = await helper.database;
    final columns = <String, Set<Object?>>{};
    for (final table in tables) {
      columns[table] = (await db.rawQuery(
        'PRAGMA table_info($table)',
      )).map((row) => row['name']).toSet();
    }
    await PerformanceProbe.measure(
      'backup.validate',
      () => compute(_validateTables, (data, columns)),
    );
    final restoredImages = images.isEmpty
        ? null
        : await receipts.restoreFolder();
    var committed = false;
    try {
      final paths = <String, String>{};
      reportBackupProgress(
        onProgress,
        BackupStage.restoringReceipts,
        completed: 0,
        total: images.length,
      );
      final entries = images.entries.toList();
      for (final entry in entries) {
        if (entry.key is! String ||
            entry.value is! String ||
            p.basename(entry.key as String) != entry.key) {
          throw const FormatException('Invalid receipt name.');
        }
      }
      for (var start = 0; start < entries.length; start += 2) {
        final end = (start + 2).clamp(0, entries.length);
        await Future.wait(
          entries.sublist(start, end).map((entry) async {
            paths[entry.key as String] = await receipts.write(
              await compute(_decodeReceipt, entry.value as String),
              folder: restoredImages,
            );
          }),
        );
        reportBackupProgress(
          onProgress,
          BackupStage.restoringReceipts,
          completed: end,
          total: images.length,
        );
      }
      final totalRows = tables.fold<int>(
        0,
        (count, table) => count + (data[table] as List).length,
      );
      var savedRows = 0;
      reportBackupProgress(
        onProgress,
        BackupStage.savingData,
        completed: 0,
        total: totalRows,
      );
      await PerformanceProbe.measure(
        'backup.write',
        () => db.transaction((txn) async {
          for (final table in tables) {
            await txn.delete(table);
          }
          await txn.delete('sms_review');
          await txn.delete('transaction_vectors');
          await ChatSchema.reset(txn);
          await txn.delete('budget_update_log');
          // Bound each platform-channel payload, keeping all batches inside the
          // same transaction so a later validation failure rolls everything back.
          for (final table in tables) {
            var batch = txn.batch();
            var pending = 0;
            for (final raw in data[table] as List) {
              final row = Map<String, Object?>.from(raw as Map);
              if (table == 'transactions') {
                row['image_path'] = paths[row['image_path']];
                if (row['amount'] is! num ||
                    (row['amount'] as num) <= 0 ||
                    !['income', 'expense'].contains(row['type']) ||
                    DateTime.tryParse('${row['date']}') == null) {
                  throw const BackupRestoreException(
                    'The backup contains a transaction with an invalid amount, type or date. Your current data was not replaced.',
                  );
                }
              }
              batch.insert(table, row);
              if (++pending == 250) {
                await batch.commit(noResult: true);
                batch = txn.batch();
                savedRows += pending;
                reportBackupProgress(
                  onProgress,
                  BackupStage.savingData,
                  completed: savedRows,
                  total: totalRows,
                );
                pending = 0;
              }
            }
            if (pending > 0) {
              await batch.commit(noResult: true);
              savedRows += pending;
              reportBackupProgress(
                onProgress,
                BackupStage.savingData,
                completed: savedRows,
                total: totalRows,
              );
            }
          }
          for (final table in [
            'transactions',
            'subscriptions',
            'budgets',
            'goals',
          ]) {
            final orphans = await txn.rawQuery(
              'SELECT id FROM $table WHERE account_id IS NOT NULL AND account_id NOT IN (SELECT id FROM accounts) LIMIT 1',
            );
            if (orphans.isNotEmpty) {
              throw BackupRestoreException(
                'The backup contains $table records linked to a missing account. Your current data was not replaced.',
              );
            }
          }
          final invalid = await txn.rawQuery(
            'SELECT c.id FROM transactions c LEFT JOIN transactions p ON c.parent_id = p.id WHERE c.parent_id IS NOT NULL AND (p.id IS NULL OR p.parent_id IS NOT NULL OR c.account_id != p.account_id OR c.type != p.type) LIMIT 1',
          );
          if (invalid.isNotEmpty) {
            throw const BackupRestoreException(
              'The backup contains invalid split transaction links. Your current data was not replaced.',
            );
          }
          final sums = await txn.rawQuery(
            'SELECT p.id FROM transactions p JOIN transactions c ON c.parent_id = p.id GROUP BY p.id HAVING ABS(p.amount - SUM(c.amount)) > 0.005 LIMIT 1',
          );
          if (sums.isNotEmpty) {
            throw const BackupRestoreException(
              'The backup contains split amounts that do not match their transaction total. Your current data was not replaced.',
            );
          }
        }),
      );
      committed = true;
    } finally {
      if (!committed && restoredImages != null) {
        await restoredImages.delete(recursive: true);
      }
    }
    reportBackupProgress(onProgress, BackupStage.schedulingReminders);
    // App-lock credentials intentionally remain device-local.
    try {
      await (reschedule?.call() ?? NotificationService().rescheduleAll());
    } catch (_) {
      /* Retry on next launch. */
    }
  }

  static void _validateRow(String table, Map<String, Object?> row) {
    final map = Map<String, dynamic>.from(row);
    switch (table) {
      case 'accounts':
        final opening = row['initial_balance'];
        if (opening != null && (opening is! num || !opening.isFinite)) {
          throw const FormatException('Invalid initial balance.');
        }
        Account.fromMap(map);
        break;
      case 'transactions':
        TransactionModel.fromMap(map);
        break;
      case 'categories':
        Category.fromMap(map);
        break;
      case 'budgets':
        Budget.fromMap(map);
        break;
      case 'goals':
        Goal.fromMap(map);
        break;
      case 'reminders':
        Reminder.fromMap(map);
        break;
      case 'appliances':
        Appliance.fromMap(map);
        break;
      case 'registered_entities':
        RegisteredEntity.fromMap(map);
        break;
      case 'subscriptions':
        SubscriptionModel.fromMap(map);
        break;
    }
  }

  static bool isPlaintextDatabase(Uint8List bytes) =>
      bytes.length >= 16 &&
      ascii.decode(bytes.sublist(0, 16), allowInvalid: true) ==
          'SQLite format 3\u0000';

  Future<Map<String, Object>> _legacy(Uint8List bytes) async {
    final dir = await Directory(
      documentsPath ?? (await getTemporaryDirectory()).path,
    ).createTemp('spendy_validate_');
    DatabaseHelper? migrated;
    try {
      final file = File(p.join(dir.path, 'legacy.db'));
      await file.writeAsBytes(bytes, flush: true);
      migrated = DatabaseHelper.legacyImport(file.path, (legacy) async {
        final check = await legacy.rawQuery('PRAGMA integrity_check');
        if (check.length != 1 || check.single.values.single != 'ok') {
          throw const BackupRestoreException(
            'This database backup is damaged or incomplete. Try another copy of the original backup.',
          );
        }
        final version = await legacy.getVersion();
        if (version < 1 || version > DatabaseHelper.schemaVersion) {
          throw BackupRestoreException(
            'This backup uses database version $version. Supported legacy versions are 1–${DatabaseHelper.schemaVersion}.',
          );
        }
        final names = (await legacy.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        )).map((row) => row['name']).toSet();
        if (!names.containsAll([
          'accounts',
          'transactions',
          'categories',
          'user_settings',
        ])) {
          throw const BackupRestoreException(
            'This file is not a complete Spendy database backup.',
          );
        }
      });
      // Validate and migrate through one connection to the disposable copy.
      final upgraded = await migrated.database;
      final data = <String, Object>{};
      for (final table in tables) {
        final rows = (await upgraded.query(
          table,
        )).map((row) => Map<String, Object?>.from(row)).toList();
        if (table == 'user_settings') {
          for (final row in rows) {
            row['pin'] = null;
            row['auth_token'] = null;
          }
        }
        data[table] = rows;
      }
      return {
        'format': 'spendy',
        'version': 1,
        'tables': data,
        'images': <String, String>{},
      };
    } finally {
      await migrated?.closeDatabase();
      await dir.delete(recursive: true);
    }
  }
}

Uint8List _encodeSnapshot(
  (Map<String, List<Map<String, Object?>>>, Map<String, Uint8List>) input,
) {
  final bytes = Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'format': 'spendy',
        'version': 1,
        'tables': input.$1,
        'images': input.$2.map(
          (key, value) => MapEntry(key, base64Encode(value)),
        ),
      }),
    ),
  );
  if (bytes.length > BackupSnapshot.maxBytes) {
    throw StateError('Backup exceeds the 50 MB limit.');
  }
  return bytes;
}

void _validateTables((Map, Map<String, Set<Object?>>) input) {
  final data = input.$1;
  final schema = input.$2;
  const tables = BackupSnapshot.tables;
  for (final table in tables) {
    final columns = schema[table]!;
    for (final raw in data[table] as List) {
      final row = Map<String, Object?>.from(raw as Map);
      final extra = row.keys.where((key) => !columns.contains(key)).toList();
      if (extra.isNotEmpty) {
        // Report schema metadata only, never financial record values.
        final names = extra
            .map(
              (key) => RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]{0,39}$').hasMatch(key)
                  ? key
                  : '[unrecognized column name]',
            )
            .take(8)
            .join(', ');
        throw BackupRestoreException(
          'Backup schema mismatch in $table: extra columns [$names]. Your current data was not replaced.',
        );
      }
      if (row['id'] is! int) {
        final id = row['id'];
        final kind = id == null
            ? 'missing/null'
            : id is String
            ? 'text'
            : id is num
            ? 'non-integer number'
            : 'unsupported type';
        throw BackupRestoreException(
          'Backup schema mismatch in $table: record ID is $kind; an integer is required. Your current data was not replaced.',
        );
      }
      try {
        BackupSnapshot._validateRow(table, row);
      } catch (_) {
        throw BackupRestoreException(
          'The backup contains a record with invalid field types or dates in $table. Your current data was not replaced.',
        );
      }
      for (final value in row.values) {
        if (value != null && value is! String && value is! num) {
          throw FormatException('Invalid field in $table');
        }
        if (value is num && !value.isFinite) {
          throw const FormatException('Invalid numeric field.');
        }
      }
    }
  }
}

Object? _decodeSnapshot(Uint8List bytes) => jsonDecode(utf8.decode(bytes));
Uint8List _decodeReceipt(String encoded) => base64Decode(encoded);
