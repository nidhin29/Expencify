import 'chat_schema.dart';
import '../../application/services/performance/performance_probe.dart';
import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'live_database_store.dart';

class DatabaseHelper {
  static const schemaVersion = 21;
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal()
    : _pathOverride = null,
      _encryptedStore = null,
      _validateLegacy = null;

  /// Plain SQLite for test fixtures and isolated legacy-backup migration copies.
  /// The live production database uses SQLCipher.
  DatabaseHelper.atPath(String path)
    : _pathOverride = path,
      _encryptedStore = null,
      _validateLegacy = null;

  /// Opens a disposable backup copy once, validating before schema migration.
  DatabaseHelper.legacyImport(
    String path,
    Future<void> Function(Database) validate,
  ) : _pathOverride = path,
      _encryptedStore = null,
      _validateLegacy = validate;
  DatabaseHelper.encrypted(LiveDatabaseStore store)
    : _pathOverride = null,
      _encryptedStore = store,
      _validateLegacy = null;
  final Future<void> Function(Database)? _validateLegacy;
  final String? _pathOverride;
  final LiveDatabaseStore? _encryptedStore;
  Future<Database>? _opening;

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _opening ??= PerformanceProbe.measure('database.open', _initDatabase);
    try {
      _database = await _opening;
      return _database!;
    } finally {
      _opening = null;
    }
  }

  Future<Database> _initDatabase() async {
    final options = OpenDatabaseOptions(
      version: schemaVersion,
      singleInstance: _validateLegacy == null,
      onConfigure: (db) async {
        await db.rawQuery('PRAGMA temp_store=MEMORY');
        if (_pathOverride == null) {
          await db.rawQuery('PRAGMA cipher_memory_security=ON');
        }
        if (_validateLegacy != null) {
          await _validateLegacy(db);
          // This isolated copy needs no concurrent readers or WAL sidecars.
          await db.rawQuery('PRAGMA journal_mode=DELETE');
        } else {
          await db.rawQuery('PRAGMA journal_mode=WAL');
        }
      },
      onOpen: _verifySchema,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    if (_pathOverride != null) {
      return databaseFactory.openDatabase(_pathOverride, options: options);
    }
    // Keep the old sqflite directory so existing installations can be migrated.
    final store =
        _encryptedStore ??
        LiveDatabaseStore(directory: await getDatabasesPath());
    return store.open(options);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE accounts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        balance REAL,
        bank_name TEXT,
        account_number TEXT,
        initial_balance REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE categories(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        icon TEXT,
        color INTEGER,
        type TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id INTEGER,
        amount REAL,
        type TEXT,
        category TEXT,
        date TEXT,
        note TEXT,
        merchant TEXT,
        is_ocr INTEGER DEFAULT 0,
        is_voice INTEGER DEFAULT 0,
        is_sms INTEGER DEFAULT 0,
        image_path TEXT,
        parent_id INTEGER,
        FOREIGN KEY (account_id) REFERENCES accounts (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE budgets(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT,
        amount REAL,
        period TEXT,
        start_date TEXT,
        account_id INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE user_settings(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        has_onboarded INTEGER DEFAULT 0,
        auth_token TEXT,
        is_dark_mode INTEGER DEFAULT 0,
        pin TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE goals(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        target_amount REAL,
        saved_amount REAL DEFAULT 0,
        target_date TEXT,
        icon TEXT DEFAULT 'savings',
        color INTEGER DEFAULT 4282532081,
        account_id INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE reminders(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        amount REAL,
        due_date TEXT,
        recurrence_anchor TEXT,
        is_recurring INTEGER DEFAULT 0,
        frequency TEXT DEFAULT 'monthly'
      )
    ''');

    await db.execute('''
      CREATE TABLE registered_entities(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        keyword TEXT UNIQUE,
        category TEXT,
        type TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE appliances(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        brand TEXT,
        purchase_date TEXT,
        amc_expiry_date TEXT,
        amc_amount REAL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS processed_sms_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        body TEXT,
        timestamp INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE subscriptions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        amount REAL,
        merchant TEXT,
        start_date TEXT,
        next_due_date TEXT,
        frequency TEXT DEFAULT 'monthly',
        is_active INTEGER DEFAULT 1,
        account_id INTEGER,
        FOREIGN KEY (account_id) REFERENCES accounts (id)
      )
    ''');

    await _createIndexes(db);
    await _insertDefaultCategories(db);
    await _insertDefaultAccount(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await _upgrade(db, oldVersion, newVersion);
    if (oldVersion < 20) {
      await db.execute('DROP INDEX IF EXISTS transactions_parent');
    }
    await _createIndexes(db);
    await _verifySchema(db);
  }

  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute(
          'ALTER TABLE user_settings ADD COLUMN has_onboarded INTEGER DEFAULT 0',
        );
      } catch (e) {
        if (!'$e'.contains('duplicate column name')) rethrow;
      }
    }
    if (oldVersion < 3) {
      try {
        await db.execute(
          'ALTER TABLE user_settings ADD COLUMN auth_token TEXT',
        );
      } catch (e) {
        if (!'$e'.contains('duplicate column name')) rethrow;
      }
    }
    if (oldVersion < 5) {
      try {
        await db.execute('ALTER TABLE transactions ADD COLUMN image_path TEXT');
      } catch (e) {
        if (!'$e'.contains('duplicate column name')) rethrow;
      }
    }
    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE transactions ADD COLUMN merchant TEXT');
      } catch (e) {
        if (!'$e'.contains('duplicate column name')) rethrow;
      }
      try {
        await db.execute(
          'ALTER TABLE user_settings ADD COLUMN is_dark_mode INTEGER DEFAULT 0',
        );
      } catch (e) {
        if (!'$e'.contains('duplicate column name')) rethrow;
      }
      try {
        await db.execute('ALTER TABLE user_settings ADD COLUMN pin TEXT');
      } catch (e) {
        if (!'$e'.contains('duplicate column name')) rethrow;
      }
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS goals(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            target_amount REAL,
            saved_amount REAL DEFAULT 0,
            target_date TEXT,
            icon TEXT DEFAULT 'savings',
            color INTEGER DEFAULT 4282532081
          )
        ''');
      } catch (e) {
        if (!'$e'.contains('duplicate column name')) rethrow;
      }
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS reminders(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            amount REAL,
            due_date TEXT,
            is_recurring INTEGER DEFAULT 0,
            frequency TEXT DEFAULT 'monthly'
          )
        ''');
      } catch (e) {
        if (!'$e'.contains('duplicate column name')) rethrow;
      }
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS appliances(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            brand TEXT,
            purchase_date TEXT,
            amc_expiry_date TEXT,
            amc_amount REAL DEFAULT 0
          )
        ''');
      } catch (e) {
        if (!'$e'.contains('duplicate column name')) rethrow;
      }
    }
    if (oldVersion < 6) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS registered_entities(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            keyword TEXT UNIQUE,
            category TEXT,
            type TEXT
          )
        ''');
      } catch (e) {
        if (!'$e'.contains('duplicate column name')) rethrow;
      }

      // Add new categories if they don't exist
      await _insertDefaultCategories(db);
    }
    if (oldVersion < 7) {
      try {
        await db.execute(
          'ALTER TABLE transactions ADD COLUMN parent_id INTEGER',
        );
      } catch (e) {
        if (!'$e'.contains('duplicate column name')) rethrow;
      }
    }
    if (oldVersion < 8) {
      try {
        await db.execute('ALTER TABLE budgets ADD COLUMN account_id INTEGER');
      } catch (e) {
        if (!'$e'.contains('duplicate column name')) rethrow;
      }
    }
    if (oldVersion < 9) {
      try {
        await db.execute('ALTER TABLE goals ADD COLUMN account_id INTEGER');
      } catch (e) {
        if (!'$e'.contains('duplicate column name')) rethrow;
      }
    }
    if (oldVersion < 10) {
      try {
        await db.execute('ALTER TABLE budgets ADD COLUMN account_id INTEGER');
      } catch (e) {
        if (!'$e'.contains('duplicate column name')) rethrow;
      }
      try {
        await db.execute('ALTER TABLE goals ADD COLUMN account_id INTEGER');
      } catch (e) {
        if (!'$e'.contains('duplicate column name')) rethrow;
      }
    }
    if (oldVersion < 11) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS processed_sms_log(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            body TEXT,
            timestamp INTEGER
          )
        ''');
      } catch (e) {
        if (!'$e'.contains('duplicate column name')) rethrow;
      }
    }
    if (oldVersion < 12) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS processed_sms_log(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            body TEXT,
            timestamp INTEGER
          )
        ''');
      } catch (e) {
        if (!'$e'.contains('duplicate column name')) rethrow;
      }
    }
    if (oldVersion < 13) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS subscriptions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            amount REAL,
            merchant TEXT,
            start_date TEXT,
            next_due_date TEXT,
            frequency TEXT DEFAULT 'monthly',
            is_active INTEGER DEFAULT 1,
            account_id INTEGER,
            FOREIGN KEY (account_id) REFERENCES accounts (id)
          )
        ''');
      } catch (e) {
        if (!'$e'.contains('duplicate column name')) rethrow;
      }
    }
    if (oldVersion < 15) {
      final columns = await db.rawQuery('PRAGMA table_info(accounts)');
      if (!columns.any((column) => column['name'] == 'initial_balance')) {
        await db.execute(
          'ALTER TABLE accounts ADD COLUMN initial_balance REAL',
        );
      }
    }
    if (oldVersion < 16) {
      final columns = await db.rawQuery('PRAGMA table_info(reminders)');
      if (!columns.any((column) => column['name'] == 'recurrence_anchor')) {
        await db.execute(
          'ALTER TABLE reminders ADD COLUMN recurrence_anchor TEXT',
        );
      }
    }
  }

  static const financialTables = [
    'transactions',
    'subscriptions',
    'budgets',
    'goals',
    'reminders',
    'appliances',
    'registered_entities',
    'processed_sms_log',
    'accounts',
    'categories',
  ];

  Future<void> _createIndexes(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS budget_update_log (delivery_key TEXT PRIMARY KEY, created_at TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS chat_state(id INTEGER PRIMARY KEY, generation INTEGER NOT NULL)',
    );
    await db.execute(
      'INSERT OR IGNORE INTO chat_state(id, generation) VALUES(1,0)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS chat_query_context(id INTEGER PRIMARY KEY, generation INTEGER NOT NULL, account_id INTEGER, question TEXT NOT NULL, question_id INTEGER, plan TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS chat_messages(id INTEGER PRIMARY KEY AUTOINCREMENT, text TEXT NOT NULL, role TEXT NOT NULL, failed INTEGER NOT NULL DEFAULT 0, prompt TEXT)',
    );
    await ChatSchema.ensure(db);
    await db.execute(
      'CREATE TABLE IF NOT EXISTS sms_review(identity TEXT PRIMARY KEY, body TEXT NOT NULL, sender TEXT, date TEXT NOT NULL, reason TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS transaction_vectors(transaction_id INTEGER PRIMARY KEY, model TEXT NOT NULL, source TEXT NOT NULL, vector BLOB NOT NULL)',
    );
    await db.execute(
      'CREATE TRIGGER IF NOT EXISTS vector_transaction_delete AFTER DELETE ON transactions BEGIN DELETE FROM transaction_vectors WHERE transaction_id = OLD.id; END',
    );
    await db.execute(
      'CREATE TRIGGER IF NOT EXISTS vector_transaction_update AFTER UPDATE ON transactions BEGIN DELETE FROM transaction_vectors WHERE transaction_id = OLD.id; END',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS transactions_account_date ON transactions(account_id, date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS transactions_parent ON transactions(parent_id, date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS transactions_date ON transactions(date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS transactions_type_date ON transactions(type, date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS sms_identity ON processed_sms_log(body)',
    );
  }

  Future<void> _verifySchema(Database db) async {
    for (final table in [...financialTables, 'user_settings']) {
      await db.query(table, limit: 0);
    }
    for (final entry in {
      'accounts': ['initial_balance'],
      'reminders': ['recurrence_anchor'],
      'transactions': ['account_id', 'parent_id', 'merchant', 'image_path'],
      'budgets': ['account_id'],
      'goals': ['account_id'],
    }.entries) {
      final columns = await db.rawQuery('PRAGMA table_info(${entry.key})');
      final names = columns.map((row) => row['name']).toSet();
      if (!names.containsAll(entry.value)) {
        throw StateError('Incomplete database migration: ${entry.key}');
      }
    }
  }

  Future<void> _insertDefaultAccount(DatabaseExecutor db) async {
    await db.insert('accounts', {
      'name': 'My Wallet',
      'balance': 0.0,
      'bank_name': 'Cash',
      'account_number': 'CASH',
    });
  }

  Future<void> _insertDefaultCategories(DatabaseExecutor db) async {
    final List<Map<String, dynamic>> defaults = [
      {
        'name': 'Salary',
        'icon': 'money',
        'color': 0xFF4CAF50,
        'type': 'income',
      },
      {
        'name': 'Transfer',
        'icon': 'sync_alt',
        'color': 0xFF2196F3,
        'type': 'income',
      },
      {
        'name': 'Refund',
        'icon': 'settings_backup_restore',
        'color': 0xFF9C27B0,
        'type': 'income',
      },
      {
        'name': 'Cashback',
        'icon': 'redeem',
        'color': 0xFFFFE082,
        'type': 'income',
      },
      {
        'name': 'Business',
        'icon': 'business',
        'color': 0xFF00BCD4,
        'type': 'income',
      },
      {
        'name': 'Investment',
        'icon': 'trending_up',
        'color': 0xFF8BC34A,
        'type': 'income',
      },
      {
        'name': 'Food',
        'icon': 'restaurant',
        'color': 0xFFF44336,
        'type': 'expense',
      },
      {
        'name': 'Fuel',
        'icon': 'local_gas_station',
        'color': 0xFF2196F3,
        'type': 'expense',
      },
      {
        'name': 'Shopping',
        'icon': 'shopping_cart',
        'color': 0xFFFF9800,
        'type': 'expense',
      },
      {
        'name': 'Entertainment',
        'icon': 'movie',
        'color': 0xFF9C27B0,
        'type': 'expense',
      },
      {
        'name': 'Health',
        'icon': 'local_hospital',
        'color': 0xFFE91E63,
        'type': 'expense',
      },
      {
        'name': 'Bills',
        'icon': 'receipt_long',
        'color': 0xFFFFEB3B,
        'type': 'expense',
      },
      {'name': 'Rent', 'icon': 'home', 'color': 0xFF795548, 'type': 'expense'},
      {
        'name': 'Education',
        'icon': 'school',
        'color': 0xFF3F51B5,
        'type': 'expense',
      },
      {
        'name': 'Grocery',
        'icon': 'local_grocery_store',
        'color': 0xFF009688,
        'type': 'expense',
      },
      {
        'name': 'Travel',
        'icon': 'flight',
        'color': 0xFF03A9F4,
        'type': 'expense',
      },
      {
        'name': 'EMI',
        'icon': 'credit_card',
        'color': 0xFFFF5722,
        'type': 'expense',
      },
      {
        'name': 'Other',
        'icon': 'category',
        'color': 0xFF607D8B,
        'type': 'expense',
      },
    ];
    for (var cat in defaults) {
      // Use IGNORE or check existence to avoid duplicates during upgrade
      final existing = await db.query(
        'categories',
        where: 'name = ? AND type = ?',
        whereArgs: [cat['name'], cat['type']],
      );
      if (existing.isEmpty) {
        await db.insert('categories', cat);
      }
    }
  }

  // --- Convenience Methods ---

  Future<void> wipeAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('transactions');
      await txn.delete('subscriptions');
      await txn.delete('registered_entities');
      await txn.delete('processed_sms_log');
      await txn.delete('sms_review');
      await txn.delete('transaction_vectors');
      await ChatSchema.reset(txn);
      await txn.delete('budget_update_log');
      await txn.delete('accounts');
      await txn.delete('budgets');
      await txn.delete('goals');
      await txn.delete('reminders');
      await txn.delete('appliances');
      await txn.delete('categories');
      await txn.delete('user_settings');
      await _insertDefaultCategories(txn);
      await _insertDefaultAccount(txn);
    });
  }

  /// Clears all financial data but keeps user_settings (user stays logged in).
  Future<void> wipeDataOnly() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('transactions');
      await txn.delete('subscriptions');
      await txn.delete('registered_entities');
      await txn.delete('processed_sms_log');
      await txn.delete('sms_review');
      await txn.delete('transaction_vectors');
      await ChatSchema.reset(txn);
      await txn.delete('budget_update_log');
      await txn.delete('accounts');
      await txn.delete('budgets');
      await txn.delete('goals');
      await txn.delete('reminders');
      await txn.delete('appliances');
      await txn.delete('categories');

      await _insertDefaultCategories(txn);
      await _insertDefaultAccount(txn);
    });
  }

  // ---- Generic CRUD ----
  Future<int> insert(String table, Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert(table, data);
  }

  Future<List<Map<String, dynamic>>> queryAll(String table) async {
    final db = await database;
    return await db.query(table);
  }

  Future<int> update(String table, Map<String, dynamic> data, int id) async {
    final db = await database;
    return await db.update(table, data, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> delete(String table, int id) async {
    final db = await database;
    return await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<dynamic>? args,
  ]) async {
    final db = await database;
    return await db.rawQuery(sql, args);
  }

  Future<int> rawUpdate(String sql, [List<dynamic>? args]) async {
    final db = await database;
    return await db.rawUpdate(sql, args);
  }

  Future<void> transaction(
    Future<void> Function(Transaction txn) action,
  ) async {
    final db = await database;
    await db.transaction(action);
  }

  Future<void> closeDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
