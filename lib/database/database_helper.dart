import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:path/path.dart';

import '../models/spoilage_entry.dart';
import '../models/item.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../models/transaction_item.dart';
import '../utils/app_logger.dart';
import '../utils/money.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static String databaseName = 'talako.db';
  static const int schemaVersion = 7;

  Database? _database;
  Future<void>? _initFuture;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    if (_initFuture != null) {
      try {
        await _initFuture;
        if (_database != null) return _database!;
      } catch (_) {
        _initFuture = null;
      }
    }
    _initFuture = _initDB(databaseName).then((db) => _database = db);
    try {
      await _initFuture;
    } catch (e) {
      _initFuture = null;
      rethrow;
    }
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);
    await _guardDatabaseFile(path);
    return await openDatabase(
      path,
      version: schemaVersion,
      onConfigure: _configureDB,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
      onOpen: _onOpen,
    );
  }

  /// Android's default SQLite error handler deletes a corrupt database during
  /// open. Validate a throwaway copy first so a corrupt live file is never
  /// destroyed and the caller can show the recovery screen.
  Future<void> _guardDatabaseFile(String path) async {
    final file = File(path);
    if (!await file.exists() || await file.length() == 0) return;

    final raf = await file.open();
    final header = await raf.read(16);
    await raf.close();
    if (String.fromCharCodes(header) != 'SQLite format 3\u0000') {
      throw Exception('Database file is not a valid SQLite database');
    }

    final probe = File('$path.preflight');
    if (await probe.exists()) await probe.delete();
    await file.copy(probe.path);
    Database? incoming;
    try {
      incoming = await openDatabase(
        probe.path,
        readOnly: true,
        singleInstance: false,
      );
      final integrity = await incoming.rawQuery('PRAGMA integrity_check');
      if (integrity.isEmpty ||
          integrity.first.values.first.toString().toLowerCase() != 'ok') {
        throw Exception('Database integrity check failed');
      }
    } finally {
      try {
        await incoming?.close();
      } catch (_) {}
      if (await probe.exists()) await probe.delete();
    }
  }

  Future<void> _configureDB(Database db) async {
    var version = 0;
    try {
      version = await db.getVersion();
    } catch (_) {}
    if (version > 0 && version < schemaVersion) {
      await db.execute('PRAGMA foreign_keys = OFF');
    } else {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }

  Future<void> _onOpen(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    await _repairStatuses(db);
  }

  Future<void> _repairStatuses(Database db) async {
    try {
      await db.rawUpdate('''
        UPDATE transactions SET status =
          CASE WHEN paid_amount >= total_amount THEN 'PAID' ELSE 'ACTIVE' END
        WHERE status <> CASE WHEN paid_amount >= total_amount THEN 'PAID' ELSE 'ACTIVE' END
      ''');
    } catch (e, s) {
      logError('status-repair', e, s);
    }
  }

  Future<void> _createDB(Database db, int version) async {
    await _createV7Tables(db);
    await _createInventoryTables(db);
    await _createIndexes(db);
  }

  Future<void> _createV7Tables(Database db, {String suffix = ''}) async {
    await db.execute('''
      CREATE TABLE items$suffix (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL COLLATE NOCASE UNIQUE,
        price INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        usage_type TEXT NOT NULL DEFAULT 'retail_only',
        stock_status TEXT NOT NULL DEFAULT 'well_stocked',
        notes TEXT,
        last_status_updated TEXT,
        last_restocked TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE customers$suffix (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE transactions$suffix (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER,
        date TEXT NOT NULL,
        total_amount INTEGER NOT NULL DEFAULT 0,
        paid_amount INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'ACTIVE',
        is_owner_consumption INTEGER NOT NULL DEFAULT 0,
        is_cash_sale INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE transaction_items$suffix (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER NOT NULL,
        item_id INTEGER,
        item_name TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1,
        price INTEGER NOT NULL DEFAULT 0,
        subtotal INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE CASCADE,
        FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE spoilage_log$suffix (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER,
        estimated_value INTEGER NOT NULL DEFAULT 0,
        note TEXT,
        date TEXT NOT NULL,
        FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE SET NULL
      )
    ''');
  }

  Future<void> _createInventoryTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS dishes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        price REAL NOT NULL,
        capital REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS dish_ingredients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        dish_id INTEGER NOT NULL,
        item_id INTEGER NOT NULL,
        FOREIGN KEY (dish_id) REFERENCES dishes(id) ON DELETE CASCADE,
        FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE,
        UNIQUE(dish_id, item_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS dish_leftovers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        dish_id INTEGER NOT NULL,
        qty INTEGER NOT NULL DEFAULT 0,
        disposition TEXT NOT NULL,
        day TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      final credits = await db.query('credits');
      await db.execute('''
        CREATE TABLE transactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customer_id INTEGER NOT NULL,
          date TEXT NOT NULL,
          total_amount REAL NOT NULL,
          paid_amount REAL NOT NULL DEFAULT 0,
          status TEXT NOT NULL DEFAULT 'ACTIVE',
          FOREIGN KEY (customer_id) REFERENCES customers(id)
        )
      ''');
      await db.execute('''
        CREATE TABLE transaction_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          transaction_id INTEGER NOT NULL,
          item_name TEXT NOT NULL,
          quantity INTEGER NOT NULL DEFAULT 1,
          price REAL NOT NULL,
          subtotal REAL NOT NULL,
          FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE CASCADE
        )
      ''');
      for (final credit in credits) {
        final txnId = await db.insert('transactions', {
          'customer_id': credit['customer_id'],
          'date': credit['timestamp'],
          'total_amount': credit['total'],
          'paid_amount': credit['paid_amount'],
          'status': (credit['paid_amount'] as num) >= (credit['total'] as num)
              ? 'PAID'
              : 'ACTIVE',
        });
        await db.insert('transaction_items', {
          'transaction_id': txnId,
          'item_name': credit['item_name'],
          'quantity': credit['quantity'],
          'price': credit['price_per_unit'],
          'subtotal': credit['total'],
        });
      }
      await db.execute('DROP TABLE IF EXISTS credits');
    }
    if (oldVersion < 3) {
      await db.execute(
          "ALTER TABLE items ADD COLUMN usage_type TEXT NOT NULL DEFAULT 'retail_only'");
      await db.execute(
          "ALTER TABLE items ADD COLUMN stock_status TEXT NOT NULL DEFAULT 'well_stocked'");
      await db.execute(
          "ALTER TABLE items ADD COLUMN freshness_status TEXT NOT NULL DEFAULT 'fresh'");
      await db.execute(
          'ALTER TABLE items ADD COLUMN perishable INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE items ADD COLUMN notes TEXT');
      await db.execute('ALTER TABLE items ADD COLUMN last_status_updated TEXT');
      await db.execute('ALTER TABLE items ADD COLUMN last_restocked TEXT');
      await db.execute('ALTER TABLE transactions ADD COLUMN dish_id INTEGER');
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN is_owner_consumption INTEGER NOT NULL DEFAULT 0');
      await _createInventoryTables(db);
    }
    if (oldVersion < 4) {
      await _ensureColumn(db, 'dishes', 'capital', 'REAL NOT NULL DEFAULT 0');
      await _ensureColumn(db, 'transaction_items', 'dish_id', 'INTEGER');
      await _ensureColumn(
          db, 'transaction_items', 'unit_capital', 'REAL NOT NULL DEFAULT 0');
      await _ensureColumn(
          db, 'transactions', 'is_cash_sale', 'INTEGER NOT NULL DEFAULT 0');
      await _ensureColumn(db,
          'transactions', 'deducted_ingredients', 'INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS dish_leftovers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          dish_id INTEGER NOT NULL,
          qty INTEGER NOT NULL DEFAULT 0,
          disposition TEXT NOT NULL,
          day TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 6) {
      await _createIndexes(db);
    }
    if (oldVersion < schemaVersion) {
      await _migrateToV7(db);
    }
  }

  Future<void> _backupBeforeV7(Database db) async {
    try {
      final source = File(db.path);
      if (!await source.exists()) return;
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final target = '${db.path}.pre_v7_$stamp.db';
      await source.copy(target);
      logInfo('Pre-v7 backup written to $target');
    } catch (e, s) {
      logError('pre-v7-backup', e, s);
      rethrow;
    }
  }

  Future<void> _migrateToV7(Database db) async {
    await _backupBeforeV7(db);

    final duplicates = await db.rawQuery('''
      SELECT LOWER(TRIM(name)) AS norm, GROUP_CONCAT(name, ' | ') AS names
      FROM items
      GROUP BY norm
      HAVING COUNT(*) > 1
    ''');
    if (duplicates.isNotEmpty) {
      final names = duplicates.map((r) => r['names']).join('; ');
      throw Exception(
          'Cannot migrate: item names differ only by case/whitespace: $names');
    }

    await _createV7Tables(db, suffix: '_v7');

    await db.execute('''
      INSERT INTO items_v7 (id, name, price, created_at, usage_type,
        stock_status, notes, last_status_updated, last_restocked)
      SELECT id, name, CAST(ROUND(price * 100) AS INTEGER), created_at,
        usage_type, stock_status, notes, last_status_updated, last_restocked
      FROM items
    ''');

    await db.execute('''
      INSERT INTO customers_v7 (id, name, created_at)
      SELECT id, name, created_at FROM customers
    ''');

    await db.execute('''
      INSERT INTO transactions_v7 (id, customer_id, date, total_amount,
        paid_amount, status, is_owner_consumption, is_cash_sale)
      SELECT id, customer_id, date,
        CAST(ROUND(total_amount * 100) AS INTEGER),
        CAST(ROUND(paid_amount * 100) AS INTEGER),
        CASE WHEN paid_amount >= total_amount THEN 'PAID' ELSE 'ACTIVE' END,
        is_owner_consumption, is_cash_sale
      FROM transactions
    ''');

    await db.execute('''
      INSERT INTO transaction_items_v7 (id, transaction_id, item_id,
        item_name, quantity, price, subtotal)
      SELECT ti.id, ti.transaction_id,
        CASE
          WHEN (SELECT COUNT(*) FROM items_v7 i
                WHERE LOWER(TRIM(i.name)) = LOWER(TRIM(ti.item_name))) = 1
          THEN (SELECT i.id FROM items_v7 i
                WHERE LOWER(TRIM(i.name)) = LOWER(TRIM(ti.item_name)) LIMIT 1)
          ELSE NULL
        END,
        ti.item_name, ti.quantity,
        CAST(ROUND(ti.price * 100) AS INTEGER),
        CAST(ROUND(ti.subtotal * 100) AS INTEGER)
      FROM transaction_items ti
    ''');

    final spoilageColumns =
        await db.rawQuery('PRAGMA table_info(spoilage_log)');
    final hasItemId =
        spoilageColumns.any((c) => c['name'] == 'item_id');
    if (hasItemId) {
      await db.execute('''
        INSERT INTO spoilage_log_v7 (id, item_id, estimated_value, note, date)
        SELECT s.id,
          CASE WHEN EXISTS (SELECT 1 FROM items_v7 i WHERE i.id = s.item_id)
            THEN s.item_id ELSE NULL END,
          CAST(ROUND(s.estimated_value * 100) AS INTEGER), s.note, s.date
        FROM spoilage_log s
      ''');
    }

    await db.execute('''
      UPDATE transactions_v7 SET customer_id = NULL
      WHERE is_owner_consumption = 1
    ''');
    await db.execute('''
      DELETE FROM customers_v7
      WHERE LOWER(TRIM(name)) = 'personal use'
        AND id NOT IN (
          SELECT customer_id FROM transactions_v7 WHERE customer_id IS NOT NULL
        )
    ''');

    await db.execute('DROP TABLE IF EXISTS transaction_items');
    await db.execute('DROP TABLE IF EXISTS spoilage_log');
    await db.execute('DROP TABLE IF EXISTS transactions');
    await db.execute('DROP TABLE IF EXISTS customers');
    await db.execute('DROP TABLE IF EXISTS items');

    await db.execute('ALTER TABLE items_v7 RENAME TO items');
    await db.execute('ALTER TABLE customers_v7 RENAME TO customers');
    await db.execute('ALTER TABLE transactions_v7 RENAME TO transactions');
    await db.execute(
        'ALTER TABLE transaction_items_v7 RENAME TO transaction_items');
    await db.execute('ALTER TABLE spoilage_log_v7 RENAME TO spoilage_log');

    await _createIndexes(db);

    final check = await db.rawQuery('PRAGMA integrity_check');
    if (check.isEmpty || check.first.values.first != 'ok') {
      throw Exception('Migration integrity check failed: $check');
    }
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_txn_date ON transactions(date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ti_txn ON transaction_items(transaction_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_txn_cash_day ON transactions(is_cash_sale, date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_txn_customer ON transactions(customer_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(LOWER(TRIM(name)))');
  }

  Future<void> _ensureColumn(
      Database db, String table, String name, String definition) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    if (!cols.any((c) => c['name'] == name)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $name $definition');
    }
  }

  Future<String> getDbFilePath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, databaseName);
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      _initFuture = null;
    }
  }

  Future<void> checkpoint() async {
    try {
      final db = await database;
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (e, s) {
      logError('db-checkpoint', e, s);
    }
  }

  // ─── Items ──────────────────────────────────────────────────────────

  Future<int> insertItem(Item item) async {
    final db = await database;
    return await db.insert('items', item.toMap());
  }

  Future<List<Item>> getAllItems(
      {String? search, bool newestFirst = true}) async {
    final db = await database;
    String? where;
    List<dynamic>? whereArgs;
    if (search != null && search.isNotEmpty) {
      where = 'name LIKE ?';
      whereArgs = ['%$search%'];
    }
    final result = await db.query(
      'items',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'created_at ${newestFirst ? 'DESC' : 'ASC'}',
    );
    return result.map((map) => Item.fromMap(map)).toList();
  }

  Future<int> updateItem(Item item) async {
    final db = await database;
    return await db.update('items', item.toMap(),
        where: 'id = ?', whereArgs: [item.id]);
  }

  Future<int> deleteItem(int id) async {
    final db = await database;
    return await db.transaction((txn) async {
      await txn.update('spoilage_log', {'item_id': null},
          where: 'item_id = ?', whereArgs: [id]);
      return txn.delete('items', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<Item?> getItemByName(String name) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT * FROM items WHERE LOWER(TRIM(name)) = LOWER(TRIM(?)) LIMIT 1',
      [name],
    );
    if (result.isEmpty) return null;
    return Item.fromMap(result.first);
  }

  Future<List<String>> getAllItemNames() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT DISTINCT item_name FROM transaction_items ORDER BY item_name ASC');
    final names = result.map((r) => r['item_name'] as String).toSet();
    final items = await db.query('items', columns: ['name']);
    names.addAll(items.map((r) => r['name'] as String));
    return names.toList()..sort();
  }

  Future<bool> isItemNameTaken(String name, {int? excludeId}) async {
    final norm = name.trim();
    if (norm.isEmpty) return false;
    final db = await database;
    final where = excludeId == null
        ? 'LOWER(TRIM(name)) = LOWER(TRIM(?))'
        : 'LOWER(TRIM(name)) = LOWER(TRIM(?)) AND id != ?';
    final args = excludeId == null ? [norm] : [norm, excludeId];
    final result =
        await db.rawQuery('SELECT 1 FROM items WHERE $where LIMIT 1', args);
    return result.isNotEmpty;
  }

  Future<Item?> getItemById(int id) async {
    final db = await database;
    final result = await db.query('items', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return Item.fromMap(result.first);
  }

  Future<int> updateItemStockStatus(int id, String statusDbValue) async {
    final db = await database;
    return await db.update(
      'items',
      {
        'stock_status': statusDbValue,
        'last_status_updated': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markItemsRestocked(List<int> itemIds) async {
    if (itemIds.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(itemIds.length, '?').join(',');
    await db.update(
      'items',
      {
        'stock_status': 'well_stocked',
        'last_restocked': DateTime.now().toIso8601String(),
        'last_status_updated': DateTime.now().toIso8601String(),
      },
      where: 'id IN ($placeholders)',
      whereArgs: itemIds,
    );
  }

  // ─── Customers ──────────────────────────────────────────────────────

  Future<int> insertCustomer(Customer customer) async {
    final db = await database;
    return await db.insert('customers', customer.toMap());
  }

  Future<List<Customer>> getAllCustomers({String? search}) async {
    final db = await database;
    String? where;
    List<dynamic>? whereArgs;
    if (search != null && search.isNotEmpty) {
      where = 'name LIKE ?';
      whereArgs = ['%$search%'];
    }
    final result = await db.query(
      'customers',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'name ASC',
    );
    return result.map((map) => Customer.fromMap(map)).toList();
  }

  Future<Customer?> getCustomerById(int id) async {
    final db = await database;
    final result =
        await db.query('customers', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return Customer.fromMap(result.first);
  }

  Future<Customer?> getCustomerByName(String name) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT * FROM customers WHERE LOWER(TRIM(name)) = LOWER(TRIM(?)) LIMIT 1',
      [name],
    );
    if (result.isEmpty) return null;
    return Customer.fromMap(result.first);
  }

  // ─── Transactions ───────────────────────────────────────────────────

  Future<List<Transaction>> getTransactionsByCustomer(int customerId) async {
    final db = await database;
    final result = await db.query(
      'transactions',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'date DESC',
    );
    return result.map((map) => Transaction.fromMap(map)).toList();
  }

  Future<List<Transaction>> getActiveTransactionsByCustomer(
      int customerId) async {
    final db = await database;
    final result = await db.query(
      'transactions',
      where:
          'customer_id = ? AND status = ? AND paid_amount < total_amount AND is_owner_consumption = 0 AND is_cash_sale = 0',
      whereArgs: [customerId, 'ACTIVE'],
      orderBy: 'date ASC',
    );
    return result.map((map) => Transaction.fromMap(map)).toList();
  }

  Future<List<Transaction>> getPaidTransactionsByCustomer(int customerId) async {
    final db = await database;
    final result = await db.query(
      'transactions',
      where:
          'customer_id = ? AND is_owner_consumption = 0 AND is_cash_sale = 0 AND paid_amount >= total_amount',
      whereArgs: [customerId],
      orderBy: 'date DESC',
    );
    return result.map((map) => Transaction.fromMap(map)).toList();
  }

  Future<int> getCustomerOutstandingBalance(int customerId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(total_amount - paid_amount), 0) as balance FROM transactions WHERE customer_id = ? AND paid_amount < total_amount AND is_owner_consumption = 0 AND is_cash_sale = 0',
      [customerId],
    );
    return (result.first['balance'] as num).toInt();
  }

  Future<List<Map<String, dynamic>>> getCustomersWithBalances() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT c.id, c.name, c.created_at,
        COALESCE(SUM(t.total_amount - t.paid_amount), 0) as balance
      FROM customers c
      INNER JOIN transactions t ON t.customer_id = c.id
      WHERE t.paid_amount < t.total_amount AND t.is_owner_consumption = 0 AND t.is_cash_sale = 0
      GROUP BY c.id
      HAVING balance > 0
    ''');
  }

  Future<Set<int>> getAllOverdueCustomerIds() async {
    final db = await database;
    final cutoff =
        DateTime.now().subtract(const Duration(days: 14)).toIso8601String();
    final result = await db.rawQuery(
      'SELECT DISTINCT customer_id FROM transactions WHERE customer_id IS NOT NULL AND paid_amount < total_amount AND is_owner_consumption = 0 AND is_cash_sale = 0 AND date < ?',
      [cutoff],
    );
    return result.map((row) => row['customer_id'] as int).toSet();
  }

  Future<bool> hasOverdueTransactions(int customerId) async {
    final db = await database;
    final cutoff =
        DateTime.now().subtract(const Duration(days: 14)).toIso8601String();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM transactions WHERE customer_id = ? AND paid_amount < total_amount AND is_owner_consumption = 0 AND is_cash_sale = 0 AND date < ?',
      [customerId, cutoff],
    );
    return (result.first['cnt'] as int) > 0;
  }

  Future<List<Map<String, dynamic>>> getSettledCustomers() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT c.id, c.name, c.created_at, MAX(t.date) as last_cleared
      FROM customers c
      INNER JOIN transactions t ON t.customer_id = c.id
      WHERE c.id NOT IN (
        SELECT DISTINCT customer_id FROM transactions WHERE paid_amount < total_amount AND is_owner_consumption = 0 AND is_cash_sale = 0
      )
      GROUP BY c.id
      ORDER BY last_cleared DESC
    ''');
  }

  Future<int> updateTransactionPayment(int transactionId, int amount) async {
    final db = await database;
    final txn =
        await db.query('transactions', where: 'id = ?', whereArgs: [transactionId]);
    if (txn.isEmpty) return 0;
    final total = (txn.first['total_amount'] as num).toInt();
    final currentPaid = (txn.first['paid_amount'] as num).toInt();
    final updatedPaid = clampMinor(currentPaid + amount, 0, total);
    final status = updatedPaid >= total ? 'PAID' : 'ACTIVE';
    return await db.update(
      'transactions',
      {'paid_amount': updatedPaid, 'status': status},
      where: 'id = ?',
      whereArgs: [transactionId],
    );
  }

  Future<List<Map<String, dynamic>>> getActiveTransactionsWithCustomer(
      {int? customerId}) async {
    final db = await database;
    String where =
        'WHERE t.paid_amount < t.total_amount AND t.is_owner_consumption = 0 AND t.is_cash_sale = 0';
    final args = <dynamic>[];
    if (customerId != null) {
      where += ' AND t.customer_id = ?';
      args.add(customerId);
    }
    return await db.rawQuery('''
      SELECT t.*, c.name as customer_name
      FROM transactions t
      INNER JOIN customers c ON c.id = t.customer_id
      $where
      ORDER BY t.date ASC
    ''', args);
  }

  Future<List<TransactionItem>> getItemsForTransactions(
      List<int> transactionIds) async {
    if (transactionIds.isEmpty) return [];
    final db = await database;
    final placeholders = List.filled(transactionIds.length, '?').join(',');
    final result = await db.rawQuery(
      'SELECT * FROM transaction_items WHERE transaction_id IN ($placeholders) ORDER BY id ASC',
      transactionIds,
    );
    return result.map((map) => TransactionItem.fromMap(map)).toList();
  }

  Future<Map<String, dynamic>?> snapshotTransaction(int transactionId) async {
    final db = await database;
    final txn = await db.query('transactions',
        where: 'id = ?', whereArgs: [transactionId]);
    if (txn.isEmpty) return null;
    final items = await db.query('transaction_items',
        where: 'transaction_id = ?', whereArgs: [transactionId]);
    return {'transaction': txn.first, 'items': items};
  }

  Future<void> restoreTransactionSnapshot(Map<String, dynamic> snapshot) async {
    final db = await database;
    final transaction =
        Map<String, dynamic>.from(snapshot['transaction'] as Map);
    final items = (snapshot['items'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    await db.transaction((txn) async {
      await txn.insert('transactions', transaction,
          conflictAlgorithm: ConflictAlgorithm.replace);
      for (final item in items) {
        await txn.insert('transaction_items', item,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<int> deleteTransaction(int transactionId) async {
    final db = await database;
    return await db.transaction((txn) async {
      await txn.delete('transaction_items',
          where: 'transaction_id = ?', whereArgs: [transactionId]);
      return txn.delete('transactions',
          where: 'id = ?', whereArgs: [transactionId]);
    });
  }

  Future<int> reverseTransactionPayment(int transactionId, int amount) async {
    final db = await database;
    final txn =
        await db.query('transactions', where: 'id = ?', whereArgs: [transactionId]);
    if (txn.isEmpty) return 0;
    final total = (txn.first['total_amount'] as num).toInt();
    final currentPaid = (txn.first['paid_amount'] as num).toInt();
    final updatedPaid = clampMinor(currentPaid - amount, 0, total);
    final status = updatedPaid >= total ? 'PAID' : 'ACTIVE';
    return await db.update(
      'transactions',
      {'paid_amount': updatedPaid, 'status': status},
      where: 'id = ?',
      whereArgs: [transactionId],
    );
  }

  Future<List<Map<String, dynamic>>> getGroupedActiveTransactions() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT c.id as customer_id, c.name as customer_name,
        SUM(t.total_amount) as total_amount,
        SUM(t.paid_amount) as paid_amount,
        COUNT(t.id) as transaction_count,
        MIN(t.date) as oldest_date,
        MAX(t.date) as latest_date
      FROM transactions t
      INNER JOIN customers c ON c.id = t.customer_id
      WHERE t.paid_amount < t.total_amount AND t.is_owner_consumption = 0 AND t.is_cash_sale = 0
      GROUP BY c.id
      ORDER BY MIN(t.date) ASC
    ''');
  }

  // ─── Transactions with items (atomic) ───────────────────────────────

  Future<int> insertTransactionWithItems(
    int? customerId,
    List<Map<String, dynamic>> items, {
    bool isOwnerConsumption = false,
    bool isCashSale = false,
  }) async {
    final db = await database;
    final date = DateTime.now().toIso8601String();
    var totalAmount = 0;
    for (final item in items) {
      totalAmount += (item['subtotal'] as num).toInt();
    }
    final paid = isCashSale ? totalAmount : 0;
    return await db.transaction<int>((txn) async {
      final txnId = await txn.insert('transactions', {
        'customer_id': customerId,
        'date': date,
        'total_amount': totalAmount,
        'paid_amount': paid,
        'status': isCashSale ? 'PAID' : 'ACTIVE',
        'is_owner_consumption': isOwnerConsumption ? 1 : 0,
        'is_cash_sale': isCashSale ? 1 : 0,
      });
      for (final item in items) {
        final itemId = await _resolveItemId(txn, item['item_name'] as String);
        await txn.insert('transaction_items', {
          'transaction_id': txnId,
          'item_id': itemId,
          'item_name': item['item_name'],
          'quantity': item['quantity'],
          'price': (item['price'] as num).toInt(),
          'subtotal': (item['subtotal'] as num).toInt(),
        });
      }
      return txnId;
    });
  }

  Future<int?> _resolveItemId(DatabaseExecutor txn, String name) async {
    final rows = await txn.rawQuery(
      'SELECT id FROM items WHERE LOWER(TRIM(name)) = LOWER(TRIM(?))',
      [name],
    );
    return rows.length == 1 ? rows.first['id'] as int : null;
  }

  // ─── Spoilage ───────────────────────────────────────────────────────

  Future<int> insertSpoilage(SpoilageEntry entry) async {
    final db = await database;
    return await db.insert('spoilage_log', entry.toMap());
  }

  Future<List<SpoilageEntry>> getSpoilageLog({int limit = 100}) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT s.*, i.name as item_name
      FROM spoilage_log s
      LEFT JOIN items i ON i.id = s.item_id
      ORDER BY s.date DESC
      LIMIT ?
    ''', [limit]);
    return result.map(SpoilageEntry.fromMap).toList();
  }

  Future<int> spoilageTotalSince(String isoSince) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(estimated_value), 0) as total FROM spoilage_log WHERE date >= ?',
      [isoSince],
    );
    return (result.first['total'] as num).toInt();
  }

  Future<Map<String, int>> markAllCustomerReceiptsPaid(int customerId) async {
    final db = await database;
    return await db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT id, total_amount, paid_amount, (total_amount - paid_amount) AS remaining
        FROM transactions
        WHERE customer_id = ? AND paid_amount < total_amount
          AND is_owner_consumption = 0 AND is_cash_sale = 0
      ''', [customerId]);
      var collected = 0;
      for (final r in rows) {
        final rem = (r['remaining'] as num).toInt();
        final total = (r['total_amount'] as num).toInt();
        collected += rem;
        await txn.update(
          'transactions',
          {'paid_amount': total, 'status': 'PAID'},
          where: 'id = ?',
          whereArgs: [r['id']],
        );
      }
      return {'settled': rows.length, 'collected': collected};
    });
  }

  Future<List<Customer>> getCustomersByRecent() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT c.id, c.name, c.created_at,
        MAX(t.date) AS last_txn
      FROM customers c
      LEFT JOIN transactions t ON t.customer_id = c.id
      GROUP BY c.id
      ORDER BY last_txn IS NULL, last_txn DESC, c.name COLLATE NOCASE ASC
    ''');
    return result
        .map((row) => Customer(
              id: row['id'] as int,
              name: row['name'] as String,
              createdAt: row['created_at'] as String,
            ))
        .toList();
  }

  // ─── Owner Consumption & Sales Intelligence ─────────────────────────

  Future<List<Map<String, dynamic>>> getOwnerConsumptionLog(
      {int limit = 200}) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT t.*, c.name as customer_name
      FROM transactions t
      LEFT JOIN customers c ON c.id = t.customer_id
      WHERE t.is_owner_consumption = 1
      ORDER BY t.date DESC
      LIMIT ?
    ''', [limit]);
    if (rows.isEmpty) return rows;
    final ids = rows.map((r) => r['id'] as int).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final itemRows = await db.rawQuery(
      'SELECT transaction_id, item_name FROM transaction_items WHERE transaction_id IN ($placeholders)',
      ids,
    );
    final namesByTxn = <int, List<String>>{};
    for (final row in itemRows) {
      namesByTxn
          .putIfAbsent(row['transaction_id'] as int, () => [])
          .add(row['item_name'] as String);
    }
    return [
      for (final r in rows)
        {
          ...r,
          'item_names': (namesByTxn[r['id']] ?? const []).join(', '),
        }
    ];
  }

  Future<Map<String, int>> getItemSaleCountsSince(String isoSince) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT LOWER(TRIM(ti.item_name)) AS norm_name, COUNT(*) AS cnt
      FROM transaction_items ti
      INNER JOIN transactions t ON t.id = ti.transaction_id
      WHERE t.date >= ? AND t.is_owner_consumption = 0
      GROUP BY norm_name
    ''', [isoSince]);
    return {
      for (final row in result)
        (row['norm_name'] as String? ?? ''): row['cnt'] as int,
    };
  }

  Future<Map<String, int>> getSalesSummarySince(String isoSince) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN is_owner_consumption = 0 THEN total_amount ELSE 0 END), 0) AS sales,
        COALESCE(SUM(CASE WHEN is_owner_consumption = 0 THEN paid_amount ELSE 0 END), 0) AS collected,
        COALESCE(SUM(CASE WHEN is_cash_sale = 1 AND is_owner_consumption = 0 THEN total_amount ELSE 0 END), 0) AS cash_sales,
        COALESCE(SUM(CASE WHEN is_owner_consumption = 1 THEN total_amount ELSE 0 END), 0) AS owner_use
      FROM transactions
      WHERE date >= ?
    ''', [isoSince]);
    final row = result.first;
    return {
      'sales': (row['sales'] as num).toInt(),
      'collected': (row['collected'] as num).toInt(),
      'cash_sales': (row['cash_sales'] as num).toInt(),
      'owner_use': (row['owner_use'] as num).toInt(),
    };
  }

  Future<List<Map<String, dynamic>>> getTopItemsSince(String isoSince,
      {int limit = 5}) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT LOWER(TRIM(ti.item_name)) AS norm_name,
        COUNT(*) AS order_count,
        SUM(ti.quantity) AS unit_count
      FROM transaction_items ti
      INNER JOIN transactions t ON t.id = ti.transaction_id
      WHERE t.date >= ? AND t.is_owner_consumption = 0
      GROUP BY norm_name
      ORDER BY order_count DESC
      LIMIT ?
    ''', [isoSince, limit]);
  }

  Future<List<TransactionItem>> getItemsByTransaction(int transactionId) async {
    final db = await database;
    final result = await db.query(
      'transaction_items',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
    );
    return result.map((map) => TransactionItem.fromMap(map)).toList();
  }

  // ─── Backup & Restore ───────────────────────────────────────────────

  static const _backupTables = [
    'items',
    'customers',
    'transactions',
    'transaction_items',
    'spoilage_log',
  ];

  Future<Map<String, dynamic>?> exportBackup() async {
    final db = await database;
    final payload = <String, dynamic>{};
    final counts = <String, int>{};
    for (final table in _backupTables) {
      final rows = await db.query(table);
      payload[table] = rows;
      counts[table] = rows.length;
    }
    final data = <String, dynamic>{
      'app': 'TalaKo',
      'version': schemaVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'record_counts': counts,
      ...payload,
    };
    data['checksum'] = _checksumOf(data);
    return data;
  }

  String _checksumOf(Map<String, dynamic> data) {
    final canonical = jsonEncode({
      'app': data['app'],
      'version': data['version'],
      'record_counts': data['record_counts'],
      for (final table in _backupTables) table: data[table] ?? const [],
    });
    var hash = 0x811c9dc5;
    for (final code in canonical.codeUnits) {
      hash ^= code;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Future<void> importBackup(Map<String, dynamic> data) async {
    final appName = data['app']?.toString() ?? '';
    if (appName != 'TalaKo' && appName != 'Sari') {
      throw Exception('Not a valid TalaKo backup file');
    }
    final version = (data['version'] as num?)?.toInt() ?? 1;
    if (version > schemaVersion) {
      throw Exception('Backup is from a newer version of TalaKo');
    }
    if (!data.containsKey('transactions') &&
        !data.containsKey('credits') &&
        !data.containsKey('transaction_items')) {
      throw Exception('Backup contains no ledger data');
    }

    final counts = data['record_counts'];
    if (counts is Map) {
      for (final table in _backupTables) {
        if (counts.containsKey(table) && data[table] is List) {
          if ((data[table] as List).length != (counts[table] as num).toInt()) {
            throw Exception('Backup record count mismatch for $table');
          }
        }
      }
    }
    if (data['checksum'] is String && counts is Map) {
      final expected = data['checksum'] as String;
      if (_checksumOf(data) != expected) {
        throw Exception('Backup checksum mismatch');
      }
    }

    final legacyUnits = version < schemaVersion;
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('dish_leftovers');
      await txn.delete('dish_ingredients');
      await txn.delete('dishes');
      await txn.delete('spoilage_log');
      await txn.delete('transaction_items');
      await txn.delete('transactions');
      await txn.delete('customers');
      await txn.delete('items');

      for (final raw in (data['items'] as List? ?? const [])) {
        await txn.insert('items', _itemRow(raw, legacyUnits));
      }
      for (final raw in (data['customers'] as List? ?? const [])) {
        await txn.insert('customers', _customerRow(raw));
      }
      for (final raw in (data['transactions'] as List? ?? const [])) {
        await txn.insert('transactions', _transactionRow(raw, legacyUnits));
      }
      for (final raw in (data['transaction_items'] as List? ?? const [])) {
        await txn.insert(
            'transaction_items', _transactionItemRow(raw, legacyUnits));
      }
      for (final raw in (data['spoilage_log'] as List? ?? const [])) {
        await txn.insert('spoilage_log', _spoilageRow(raw, legacyUnits));
      }

      if (!data.containsKey('transactions') &&
          data.containsKey('credits')) {
        for (final raw in (data['credits'] as List)) {
          final credit = raw as Map;
          final total = legacyUnits
              ? majorToMinor(credit['total'] as num)
              : (credit['total'] as num).toInt();
          final paid = legacyUnits
              ? majorToMinor(credit['paid_amount'] as num)
              : (credit['paid_amount'] as num).toInt();
          final txnId = await txn.insert('transactions', {
            'customer_id': credit['customer_id'],
            'date': credit['timestamp'],
            'total_amount': total,
            'paid_amount': paid,
            'status': paid >= total ? 'PAID' : 'ACTIVE',
          });
          await txn.insert('transaction_items', {
            'transaction_id': txnId,
            'item_name': credit['item_name'],
            'quantity': credit['quantity'],
            'price': legacyUnits
                ? majorToMinor(credit['price_per_unit'] as num)
                : (credit['price_per_unit'] as num).toInt(),
            'subtotal': total,
          });
        }
      }

      if (data.containsKey('dishes')) {
        for (final dish in (data['dishes'] as List)) {
          await txn.insert('dishes', Map<String, dynamic>.from(dish as Map));
        }
      }
      if (data.containsKey('dish_ingredients')) {
        for (final link in (data['dish_ingredients'] as List)) {
          await txn.insert(
              'dish_ingredients', Map<String, dynamic>.from(link as Map));
        }
      }
      if (data.containsKey('dish_leftovers')) {
        for (final entry in (data['dish_leftovers'] as List)) {
          await txn.insert(
              'dish_leftovers', Map<String, dynamic>.from(entry as Map));
        }
      }

      await txn.rawUpdate('''
        UPDATE transactions SET customer_id = NULL
        WHERE is_owner_consumption = 1
      ''');
      await txn.rawUpdate('''
        UPDATE transactions SET status =
          CASE WHEN paid_amount >= total_amount THEN 'PAID' ELSE 'ACTIVE' END
      ''');
      await txn.rawDelete('''
        DELETE FROM customers
        WHERE LOWER(TRIM(name)) = 'personal use'
          AND id NOT IN (
            SELECT customer_id FROM transactions WHERE customer_id IS NOT NULL
          )
      ''');
    });
  }

  Map<String, dynamic> _itemRow(dynamic raw, bool legacyUnits) {
    final map = Map<String, dynamic>.from(raw as Map);
    final price = (map['price'] as num?) ?? 0;
    return {
      if (map['id'] != null) 'id': map['id'],
      'name': map['name']?.toString() ?? '',
      'price': legacyUnits ? majorToMinor(price) : price.toInt(),
      'created_at': map['created_at']?.toString() ??
          DateTime.now().toIso8601String(),
      'usage_type': map['usage_type']?.toString() ?? 'retail_only',
      'stock_status': map['stock_status']?.toString() ?? 'well_stocked',
      'notes': map['notes'],
      'last_status_updated': map['last_status_updated'],
      'last_restocked': map['last_restocked'],
    };
  }

  Map<String, dynamic> _customerRow(dynamic raw) {
    final map = Map<String, dynamic>.from(raw as Map);
    return {
      if (map['id'] != null) 'id': map['id'],
      'name': map['name']?.toString() ?? '',
      'created_at': map['created_at']?.toString() ??
          DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic> _transactionRow(dynamic raw, bool legacyUnits) {
    final map = Map<String, dynamic>.from(raw as Map);
    final total = (map['total_amount'] as num?) ?? 0;
    final paid = (map['paid_amount'] as num?) ?? 0;
    final totalMinor = legacyUnits ? majorToMinor(total) : total.toInt();
    final paidMinor = legacyUnits ? majorToMinor(paid) : paid.toInt();
    return {
      if (map['id'] != null) 'id': map['id'],
      'customer_id': map['customer_id'],
      'date': map['date']?.toString() ?? DateTime.now().toIso8601String(),
      'total_amount': totalMinor,
      'paid_amount': paidMinor,
      'status': paidMinor >= totalMinor ? 'PAID' : 'ACTIVE',
      'is_owner_consumption': (map['is_owner_consumption'] as num? ?? 0).toInt(),
      'is_cash_sale': (map['is_cash_sale'] as num? ?? 0).toInt(),
    };
  }

  Map<String, dynamic> _transactionItemRow(dynamic raw, bool legacyUnits) {
    final map = Map<String, dynamic>.from(raw as Map);
    final price = (map['price'] as num?) ?? 0;
    final subtotal = (map['subtotal'] as num?) ?? 0;
    return {
      if (map['id'] != null) 'id': map['id'],
      'transaction_id': map['transaction_id'],
      'item_id': map['item_id'],
      'item_name': map['item_name']?.toString() ?? '',
      'quantity': (map['quantity'] as num? ?? 1).toInt(),
      'price': legacyUnits ? majorToMinor(price) : price.toInt(),
      'subtotal': legacyUnits ? majorToMinor(subtotal) : subtotal.toInt(),
    };
  }

  Map<String, dynamic> _spoilageRow(dynamic raw, bool legacyUnits) {
    final map = Map<String, dynamic>.from(raw as Map);
    final value = (map['estimated_value'] as num?) ?? 0;
    return {
      if (map['id'] != null) 'id': map['id'],
      'item_id': map['item_id'],
      'estimated_value': legacyUnits ? majorToMinor(value) : value.toInt(),
      'note': map['note'],
      'date': map['date']?.toString() ?? DateTime.now().toIso8601String(),
    };
  }

  /// Validates an incoming raw database without touching the live one.
  Future<void> validateRawDatabase(String sourcePath) async {
    final src = File(sourcePath);
    if (!await src.exists()) throw Exception('Database file not found');
    await _guardDatabaseFile(sourcePath);
    Database? incoming;
    try {
      incoming = await openDatabase(sourcePath,
          readOnly: true, singleInstance: false);
      final version = await incoming.getVersion();
      if (version > schemaVersion) {
        throw Exception('Database is from a newer version of TalaKo');
      }
    } finally {
      await incoming?.close();
    }
  }

  /// Replaces the live database with [sourcePath] after validation.
  /// The original stays in place until validation succeeds.
  Future<void> restoreRawDatabase(String sourcePath) async {
    await validateRawDatabase(sourcePath);
    final destination = await getDbFilePath();
    if (File(sourcePath).absolute.path == File(destination).absolute.path) {
      await close();
      return;
    }
    await close();
    for (final suffix in ['-wal', '-shm']) {
      final sidecar = File('$destination$suffix');
      if (await sidecar.exists()) await sidecar.delete();
    }
    await File(sourcePath).copy(destination);
  }
}
