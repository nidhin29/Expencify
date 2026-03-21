import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'expencify.db');
    return await openDatabase(
      path,
      version: 9,
      onConfigure: (db) async {
        await db.rawQuery('PRAGMA journal_mode=WAL');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE accounts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        balance REAL,
        bank_name TEXT,
        account_number TEXT
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
        start_date TEXT
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
        color INTEGER DEFAULT 4282532081
      )
    ''');

    await db.execute('''
      CREATE TABLE reminders(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        amount REAL,
        due_date TEXT,
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

    await _insertDefaultCategories(db);
    await _insertDefaultAccount(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute(
          'ALTER TABLE user_settings ADD COLUMN has_onboarded INTEGER DEFAULT 0',
        );
      } catch (_) {}
    }
    if (oldVersion < 3) {
      try {
        await db.execute(
          'ALTER TABLE user_settings ADD COLUMN auth_token TEXT',
        );
      } catch (_) {}
    }
    if (oldVersion < 5) {
      try {
        await db.execute('ALTER TABLE transactions ADD COLUMN image_path TEXT');
      } catch (_) {}
    }
    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE transactions ADD COLUMN merchant TEXT');
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE user_settings ADD COLUMN is_dark_mode INTEGER DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE user_settings ADD COLUMN pin TEXT');
      } catch (_) {}
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
      } catch (_) {}
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
      } catch (_) {}
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
      } catch (_) {}
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
      } catch (_) {}

      // Add new categories if they don't exist
      await _insertDefaultCategories(db);
    }
    if (oldVersion < 7) {
      try {
        await db.execute(
          'ALTER TABLE transactions ADD COLUMN parent_id INTEGER',
        );
      } catch (_) {}
    }
    if (oldVersion < 8) {
      try {
        await db.execute('ALTER TABLE budgets ADD COLUMN account_id INTEGER');
      } catch (_) {}
    }
    if (oldVersion < 9) {
      try {
        await db.execute('ALTER TABLE goals ADD COLUMN account_id INTEGER');
      } catch (_) {}
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
      await txn.delete('accounts');
      await txn.delete('budgets');
      await txn.delete('goals');
      await txn.delete('reminders');
      await txn.delete('appliances');
      await txn.delete('categories');
      await txn.delete('user_settings');
    });
  }

  /// Clears all financial data but keeps user_settings (user stays logged in).
  Future<void> wipeDataOnly() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('transactions');
      await txn.delete('accounts');
      await txn.delete('budgets');
      await txn.delete('goals');
      await txn.delete('reminders');
      await txn.delete('appliances');
      await txn.delete('categories');
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
}
