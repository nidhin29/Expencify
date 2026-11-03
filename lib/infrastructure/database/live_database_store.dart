import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart'
    show Database, DatabaseException, OpenDatabaseOptions;
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

class DatabaseEncryptionException implements Exception {
  final String message;
  const DatabaseEncryptionException(this.message);
  @override
  String toString() => message;
}

abstract interface class DatabaseKeyStore {
  Future<String?> read();
  Future<void> write(String key);
}

class SecureDatabaseKeyStore implements DatabaseKeyStore {
  static const keyName = 'spendy_database_key_v1';
  final FlutterSecureStorage storage;
  final String name;
  const SecureDatabaseKeyStore({
    this.storage = const FlutterSecureStorage(),
    this.name = keyName,
  });
  @override
  Future<String?> read() => storage.read(key: name);
  @override
  Future<void> write(String key) => storage.write(key: name, value: key);
}

abstract interface class DatabaseCipherDriver {
  Future<Database> open(
    String path, {
    String? password,
    OpenDatabaseOptions? options,
  });
  Future<void> exportPlaintext(String source, String target, String password);
  Future<void> verifyEncrypted(String path, String password);
}

class SqlCipherDriver implements DatabaseCipherDriver {
  const SqlCipherDriver();
  @override
  Future<Database> open(
    String path, {
    String? password,
    OpenDatabaseOptions? options,
  }) => cipher.openDatabase(
    path,
    password: password,
    version: options?.version,
    onConfigure: options?.onConfigure,
    onCreate: options?.onCreate,
    onUpgrade: options?.onUpgrade,
    onDowngrade: options?.onDowngrade,
    onOpen: options?.onOpen,
    readOnly: options?.readOnly ?? false,
    singleInstance: options?.singleInstance ?? false,
  );

  Future<void> _requireCipher(Database db) async {
    final version = await db.rawQuery('PRAGMA cipher_version');
    if (version.isEmpty || version.first.values.first.toString().isEmpty) {
      throw const DatabaseEncryptionException(
        'The database encryption engine is unavailable.',
      );
    }
  }

  @override
  Future<void> verifyEncrypted(String path, String password) async {
    final file = File(path);
    if (!await file.exists() ||
        await LiveDatabaseStore.hasPlaintextHeader(file)) {
      throw const DatabaseEncryptionException(
        'Encrypted database verification failed.',
      );
    }
    final db = await open(
      path,
      password: password,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      await _requireCipher(db);
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      if (integrity.length != 1 || integrity.single.values.single != 'ok') {
        throw const DatabaseEncryptionException(
          'Database integrity verification failed.',
        );
      }
      if ((await db.rawQuery('PRAGMA cipher_integrity_check')).isNotEmpty) {
        throw const DatabaseEncryptionException(
          'Encrypted page authentication failed.',
        );
      }
    } finally {
      await db.close();
    }
  }

  @override
  Future<void> exportPlaintext(
    String source,
    String target,
    String password,
  ) async {
    // Read-only validation avoids a native writable-open corruption handler
    // deleting the original file before a safe copy exists.
    final original = await open(
      source,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      await _requireCipher(original);
      final integrity = await original.rawQuery('PRAGMA integrity_check');
      if (integrity.length != 1 || integrity.single.values.single != 'ok') {
        throw const DatabaseEncryptionException(
          'The original database failed integrity verification.',
        );
      }
    } finally {
      await original.close();
    }
    final db = await open(source);
    var attached = false;
    try {
      await _requireCipher(db);
      await db.rawQuery('PRAGMA temp_store=MEMORY');
      await db.execute('ATTACH DATABASE ? AS encrypted_migration KEY ?', [
        target,
        password,
      ]);
      attached = true;
      await db.transaction((txn) async {
        await txn.rawQuery("SELECT sqlcipher_export('encrypted_migration')");
        final version = await txn.getVersion();
        await txn.execute('PRAGMA encrypted_migration.user_version = $version');
        final tables = await txn.rawQuery(
          "SELECT name FROM main.sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        );
        for (final table in tables) {
          final name = '"${(table['name'] as String).replaceAll('"', '""')}"';
          final sourceCount = (await txn.rawQuery(
            'SELECT COUNT(*) AS count FROM main.$name',
          )).single['count'];
          final targetCount = (await txn.rawQuery(
            'SELECT COUNT(*) AS count FROM encrypted_migration.$name',
          )).single['count'];
          final difference = await txn.rawQuery(
            'SELECT * FROM main.$name EXCEPT SELECT * FROM encrypted_migration.$name LIMIT 1',
          );
          if (sourceCount != targetCount || difference.isNotEmpty) {
            throw const DatabaseEncryptionException(
              'The encrypted copy did not match the original database.',
            );
          }
        }
      });
    } finally {
      try {
        if (attached) await db.execute('DETACH DATABASE encrypted_migration');
      } finally {
        await db.close();
      }
    }
  }
}

/// Owns the device-local database key and crash-safe plaintext-to-cipher switch.
/// A separate, nonfinancial SQLite file serializes initialization across isolates.
class LiveDatabaseStore {
  static const legacyFileName = 'expencify.db';
  static const encryptedFileName = 'expencify.encrypted.db';
  final String directory;
  final DatabaseKeyStore keyStore;
  final DatabaseCipherDriver driver;
  final Duration lockTimeout;
  LiveDatabaseStore({
    required this.directory,
    DatabaseKeyStore? keyStore,
    DatabaseCipherDriver? driver,
    this.lockTimeout = const Duration(minutes: 2),
  }) : keyStore = keyStore ?? const SecureDatabaseKeyStore(),
       driver = driver ?? const SqlCipherDriver();

  String get encryptedPath => p.join(directory, encryptedFileName);
  String get legacyPath => p.join(directory, legacyFileName);
  String get stagingPath => '$encryptedPath.migrating';

  static Future<bool> hasPlaintextHeader(File file) async {
    final handle = await file.open();
    try {
      final header = await handle.read(16);
      return header.length == 16 &&
          ascii.decode(header, allowInvalid: true) == 'SQLite format 3\u0000';
    } finally {
      await handle.close();
    }
  }

  Future<Database> open(OpenDatabaseOptions options) async {
    await Directory(directory).create(recursive: true);
    try {
      return await _locked(() => _openLocked(options));
    } on DatabaseEncryptionException {
      rethrow;
    } catch (_) {
      // Native SQL errors may include bound arguments: do not expose the key.
      throw const DatabaseEncryptionException(
        'The encrypted database could not be opened. Existing data has been preserved.',
      );
    }
  }

  Future<T> _locked<T>(Future<T> Function() action) async {
    final deadline = DateTime.now().add(lockTimeout);
    while (true) {
      Database? gate;
      try {
        gate = await driver.open(
          p.join(directory, 'spendy_initialization.lock.db'),
          options: OpenDatabaseOptions(
            singleInstance: false,
            onConfigure: (db) async {
              await db.rawQuery('PRAGMA busy_timeout = 0');
              // WAL allows another isolate to open/read the lock file while its
              // write lock is held. A busy BEGIN returns immediately, not on the
              // plugin's worker thread waiting for a commit queued behind itself.
              await db.rawQuery('PRAGMA journal_mode=WAL');
            },
          ),
        );
        return await gate.transaction((_) => action());
      } on DatabaseException catch (e) {
        final code = e.getResultCode();
        if (code != 5 &&
            code != 6 &&
            !e.toString().toLowerCase().contains('database is locked')) {
          rethrow;
        }
        if (DateTime.now().isAfter(deadline)) {
          throw const DatabaseEncryptionException(
            'Database initialization is busy. Please retry.',
          );
        }
      } finally {
        await gate?.close();
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<Database> _openLocked(OpenDatabaseOptions options) async {
    final encrypted = File(encryptedPath);
    final legacy = File(legacyPath);
    final staging = File(stagingPath);
    var key = await keyStore.read();
    if (key == null) {
      if (await encrypted.exists() || await staging.exists()) {
        throw const DatabaseEncryptionException(
          'The database key is unavailable. Unlock your device and retry; do not clear app storage.',
        );
      }
      if (await legacy.exists() &&
          await legacy.length() > 0 &&
          !await hasPlaintextHeader(legacy)) {
        throw const DatabaseEncryptionException(
          'The existing database is not a supported plaintext database.',
        );
      }
      final random = Random.secure();
      key = base64Encode(List<int>.generate(32, (_) => random.nextInt(256)));
      await keyStore.write(key);
      if (await keyStore.read() != key) {
        throw const DatabaseEncryptionException(
          'The database key could not be saved securely.',
        );
      }
    }
    try {
      if (base64Decode(key).length != 32) throw const FormatException();
    } catch (_) {
      throw const DatabaseEncryptionException(
        'The stored database key is invalid.',
      );
    }

    if (!await encrypted.exists() && await legacy.exists()) {
      if (await legacy.length() > 0 && !await hasPlaintextHeader(legacy)) {
        throw const DatabaseEncryptionException(
          'The existing database could not be migrated safely.',
        );
      }
      await _removeDatabaseFiles(stagingPath);
      await driver.exportPlaintext(legacyPath, stagingPath, key);
      await driver.verifyEncrypted(stagingPath, key);
      await staging.rename(encryptedPath);
    }
    // The plugin's read-only connection disables its destructive corruption
    // handler. Reject a wrong key or corrupt file before any writable open.
    final existed = await encrypted.exists();
    if (existed) await driver.verifyEncrypted(encryptedPath, key);
    final db = await driver.open(
      encryptedPath,
      password: key,
      options: options,
    );
    try {
      // New installations also verify the cipher rather than accepting a driver
      // that silently ignores a key. Checking on this connection includes WAL.
      final version = await db.rawQuery('PRAGMA cipher_version');
      if (version.isEmpty || version.first.values.first.toString().isEmpty) {
        throw const DatabaseEncryptionException(
          'The database encryption engine is unavailable.',
        );
      }
      if (!existed) await driver.verifyEncrypted(encryptedPath, key);
      if (await legacy.exists()) await _removeDatabaseFiles(legacyPath);
      await _removeDatabaseFiles(stagingPath);
      return db;
    } catch (_) {
      await db.close();
      rethrow;
    }
  }

  Future<void> _removeDatabaseFiles(String path) async {
    // Only fixed database filenames underneath this store's private directory.
    for (final suffix in ['-wal', '-shm', '-journal', '']) {
      final file = File('$path$suffix');
      if (await file.exists()) await file.delete();
    }
  }
}
