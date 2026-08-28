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
  /// Overridable so test suites can isolate their databases from each other.
  static String databaseName = 'talako.db';
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
    return await openDatabase(
      path,
      version: 6,
      onConfigure: _configureDB,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  /// SQLite ignores foreign keys (and therefore ON DELETE CASCADE) unless
  /// this pragma is set on every connection.
  Future<void> _configureDB(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        price REAL NOT NULL,
        created_at TEXT NOT NULL,
        usage_type TEXT NOT NULL DEFAULT 'retail_only',
        stock_status TEXT NOT NULL DEFAULT 'well_stocked',
        freshness_status TEXT NOT NULL DEFAULT 'fresh',
        perishable INTEGER NOT NULL DEFAULT 0,
        notes TEXT,
        last_status_updated TEXT,
        last_restocked TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        total_amount REAL NOT NULL,
        paid_amount REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'ACTIVE',
        dish_id INTEGER,
        is_owner_consumption INTEGER NOT NULL DEFAULT 0,
        is_cash_sale INTEGER NOT NULL DEFAULT 0,
        deducted_ingredients INTEGER NOT NULL DEFAULT 0,
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
        dish_id INTEGER,
        unit_capital REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE CASCADE
      )
    ''');
    await _createInventoryTables(db);
    await _createIndexes(db);
  }

  Future<void> _createInventoryTables(Database db) async {
    await db.execute('''
      CREATE TABLE dishes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        price REAL NOT NULL,
        capital REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE dish_ingredients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        dish_id INTEGER NOT NULL,
        item_id INTEGER NOT NULL,
        FOREIGN KEY (dish_id) REFERENCES dishes(id) ON DELETE CASCADE,
        FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE,
        UNIQUE(dish_id, item_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE spoilage_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL,
        estimated_value REAL NOT NULL,
        note TEXT,
        date TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE dish_leftovers (
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
          'status': (credit['paid_amount'] as num) >= (credit['total'] as num) ? 'PAID' : 'ACTIVE',
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
      await db.execute('ALTER TABLE items ADD COLUMN perishable INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE items ADD COLUMN notes TEXT');
      await db.execute('ALTER TABLE items ADD COLUMN last_status_updated TEXT');
      await db.execute('ALTER TABLE items ADD COLUMN last_restocked TEXT');
      await db.execute('ALTER TABLE transactions ADD COLUMN dish_id INTEGER');
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN is_owner_consumption INTEGER NOT NULL DEFAULT 0');
      await _createInventoryTables(db);
    }
    if (oldVersion < 4) {
      // Real v3 installs carry pre-v4 shapes; guarded ALTERs are idempotent.
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
  }

  /// Hot-path indexes. Safe on every shape: called after all tables and
  /// columns exist (end of onCreate / final upgrade step).
  Future<void> _createIndexes(Database db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_txn_date ON transactions(date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ti_txn ON transaction_items(transaction_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ti_dish ON transaction_items(dish_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_txn_cash_day ON transactions(is_cash_sale, date)');
  }


  /// Adds [name] to [table] only when missing - safe against partially
  /// upgraded databases and double-running migration blocks.
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

  Future<List<Item>> getAllItems({String? search, bool newestFirst = true}) async {
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
    return await db.update('items', item.toMap(), where: 'id = ?', whereArgs: [item.id]);
  }

  Future<int> deleteItem(int id) async {
    final db = await database;
    return await db.delete('items', where: 'id = ?', whereArgs: [id]);
  }

  Future<Item?> getItemByName(String name) async {
    final db = await database;
    final result = await db.query('items', where: 'name = ?', whereArgs: [name]);
    if (result.isEmpty) return null;
    return Item.fromMap(result.first);
  }

  Future<List<String>> getAllItemNames() async {
    final db = await database;
    final result = await db.rawQuery('SELECT DISTINCT item_name FROM transaction_items ORDER BY item_name ASC');
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
    final result = await db.rawQuery('SELECT 1 FROM items WHERE $where LIMIT 1', args);
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


  /// Restocking resets the shelf status to well-stocked and stamps when the
  /// fresh supply arrived (drives "days since bought" hints).
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
    final result = await db.query('customers', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return Customer.fromMap(result.first);
  }

  Future<Customer?> getCustomerByName(String name) async {
    final db = await database;
    final result = await db.query('customers', where: 'name = ?', whereArgs: [name]);
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

  Future<List<Transaction>> getActiveTransactionsByCustomer(int customerId) async {
    final db = await database;
    final result = await db.query(
      'transactions',
      where: 'customer_id = ? AND status = ? AND paid_amount < total_amount AND is_owner_consumption = 0 AND is_cash_sale = 0',
      whereArgs: [customerId, 'ACTIVE'],
      orderBy: 'date ASC',
    );
    return result.map((map) => Transaction.fromMap(map)).toList();
  }

  Future<List<Transaction>> getPaidTransactionsByCustomer(int customerId) async {
    final db = await database;
    final result = await db.query(
      'transactions',
      where: 'customer_id = ? AND is_owner_consumption = 0 AND is_cash_sale = 0 AND (status = ? OR paid_amount >= total_amount)',
      whereArgs: [customerId, 'PAID'],
      orderBy: 'date DESC',
    );
    return result.map((map) => Transaction.fromMap(map)).toList();
  }

  Future<double> getCustomerOutstandingBalance(int customerId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(total_amount - paid_amount), 0) as balance FROM transactions WHERE customer_id = ? AND paid_amount < total_amount AND is_owner_consumption = 0 AND is_cash_sale = 0',
      [customerId],
    );
    return (result.first['balance'] as num).toDouble();
  }

  Future<List<Map<String, dynamic>>> getCustomersWithBalances() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT c.id, c.name, c.created_at,
        COALESCE(SUM(t.total_amount - t.paid_amount), 0) as balance
      FROM customers c
      INNER JOIN transactions t ON t.customer_id = c.id
      WHERE t.paid_amount < t.total_amount AND t.is_owner_consumption = 0 AND is_cash_sale = 0
      GROUP BY c.id
      HAVING balance > 0
    ''');
  }

  Future<Set<int>> getAllOverdueCustomerIds() async {
    final db = await database;
    final cutoff = DateTime.now().subtract(const Duration(days: 14)).toIso8601String();
    final result = await db.rawQuery(
      'SELECT DISTINCT customer_id FROM transactions WHERE paid_amount < total_amount AND is_owner_consumption = 0 AND is_cash_sale = 0 AND date < ?',
      [cutoff],
    );
    return result.map((row) => row['customer_id'] as int).toSet();
  }

  Future<bool> hasOverdueTransactions(int customerId) async {
    final db = await database;
    final cutoff = DateTime.now().subtract(const Duration(days: 14)).toIso8601String();
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

  Future<int> updateTransactionPayment(int transactionId, double newPaidAmount) async {
    final db = await database;
    final txn = await db.query('transactions', where: 'id = ?', whereArgs: [transactionId]);
    if (txn.isEmpty) return 0;
    final total = (txn.first['total_amount'] as num).toDouble();
    final currentPaid = (txn.first['paid_amount'] as num).toDouble();
    final updatedPaid = clampMoney(currentPaid + newPaidAmount, 0, double.infinity);
    final status = moneyEquals(updatedPaid, total) || updatedPaid >= total ? 'PAID' : 'ACTIVE';
    return await db.update(
      'transactions',
      {'paid_amount': updatedPaid, 'status': status},
      where: 'id = ?',
      whereArgs: [transactionId],
    );
  }

  Future<List<Map<String, dynamic>>> getActiveTransactionsWithCustomer({int? customerId}) async {
    final db = await database;
    String where = 'WHERE t.paid_amount < t.total_amount AND t.is_owner_consumption = 0 AND is_cash_sale = 0';
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

  Future<List<TransactionItem>> getItemsForTransactions(List<int> transactionIds) async {
    if (transactionIds.isEmpty) return [];
    final db = await database;
    final placeholders = List.filled(transactionIds.length, '?').join(',');
    final result = await db.rawQuery(
      'SELECT * FROM transaction_items WHERE transaction_id IN ($placeholders) ORDER BY id ASC',
      transactionIds,
    );
    return result.map((map) => TransactionItem.fromMap(map)).toList();
  }

  Future<int> deleteTransaction(int transactionId) async {
    final db = await database;
    await db.delete('transaction_items', where: 'transaction_id = ?', whereArgs: [transactionId]);
    return await db.delete('transactions', where: 'id = ?', whereArgs: [transactionId]);
  }

  Future<int> reverseTransactionPayment(int transactionId, double amount) async {
    final db = await database;
    final txn = await db.query('transactions', where: 'id = ?', whereArgs: [transactionId]);
    if (txn.isEmpty) return 0;
    final total = (txn.first['total_amount'] as num).toDouble();
    final currentPaid = (txn.first['paid_amount'] as num).toDouble();
    final updatedPaid = clampMoney(currentPaid - amount, 0, total);
    final status = moneyEquals(updatedPaid, total) || updatedPaid >= total ? 'PAID' : 'ACTIVE';
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
      WHERE t.paid_amount < t.total_amount AND t.is_owner_consumption = 0 AND is_cash_sale = 0
      GROUP BY c.id
      ORDER BY MIN(t.date) ASC
    ''');
  }

  // ─── Transactions with items (atomic) ───────────────────────────────

  Future<int> insertTransactionWithItems(
    int customerId,
    List<Map<String, dynamic>> items, {
    bool isOwnerConsumption = false,
    bool isCashSale = false,
    bool deductedIngredients = false,
    int? dishId,
  }) async {
    final db = await database;
    final date = DateTime.now().toIso8601String();
    double totalAmount = 0;
    for (final item in items) {
      totalAmount += (item['subtotal'] as num).toDouble();
    }
    totalAmount = roundMoney(totalAmount);
    // A cash sale is settled the moment it happens - it must never surface
    // as debt anywhere, even if a future query forgets the flag.
    final paid = isCashSale ? totalAmount : 0.0;
    return await db.transaction<int>((txn) async {
      final txnId = await txn.insert('transactions', {
        'customer_id': customerId,
        'date': date,
        'total_amount': totalAmount,
        'paid_amount': paid,
        'status': isCashSale ? 'PAID' : 'ACTIVE',
        'is_owner_consumption': isOwnerConsumption ? 1 : 0,
        'is_cash_sale': isCashSale ? 1 : 0,
        'deducted_ingredients': deductedIngredients ? 1 : 0,
        if (dishId != null) 'dish_id': dishId,
      });
      for (final item in items) {
        await txn.insert('transaction_items', {
          'transaction_id': txnId,
          'item_name': item['item_name'],
          'quantity': item['quantity'],
          'price': item['price'],
          'subtotal': roundMoney((item['subtotal'] as num).toDouble()),
          if (item['dish_id'] != null) 'dish_id': item['dish_id'],
          'unit_capital': (item['unit_capital'] as num?)?.toDouble() ?? 0,
        });
      }
      return txnId;
    });
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

  Future<double> spoilageTotalSince(String isoSince) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(estimated_value), 0) as total FROM spoilage_log WHERE date >= ?',
      [isoSince],
    );
    return (result.first['total'] as num).toDouble();
  }

  /// Marks every unpaid credit receipt of [customerId] as fully paid.
  /// Cash tap-sales and owner-use rows are structurally excluded.
  /// Returns the number of receipts settled and the amount collected.
  Future<Map<String, double>> markAllCustomerReceiptsPaid(int customerId) async {
    final db = await database;
    return await db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT id, total_amount, paid_amount, (total_amount - paid_amount) AS remaining
        FROM transactions
        WHERE customer_id = ? AND paid_amount < total_amount
          AND is_owner_consumption = 0 AND is_cash_sale = 0
      ''', [customerId]);
      double collected = 0;
      for (final r in rows) {
        final rem = (r['remaining'] as num).toDouble();
        final total = (r['total_amount'] as num).toDouble();
        collected += rem;
        await txn.update(
          'transactions',
          {'paid_amount': roundMoney(total), 'status': 'PAID'},
          where: 'id = ?',
          whereArgs: [r['id']],
        );
      }
      return {'settled': rows.length.toDouble(), 'collected': collected};
    });
  }

  /// Customers ordered by most recent transaction first; never-used ones
  /// trail alphabetically. Powers Add-Credit suggestions.
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
    return result.map((row) => Customer(
          id: row['id'] as int,
          name: row['name'] as String,
          createdAt: row['created_at'] as String,
        )).toList();
  }

  // ─── Owner Consumption & Sales Intelligence ─────────────────────────

  Future<List<Map<String, dynamic>>> getOwnerConsumptionLog({int limit = 200}) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT t.*, c.name as customer_name
      FROM transactions t
      INNER JOIN customers c ON c.id = t.customer_id
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
      namesByTxn.putIfAbsent(row['transaction_id'] as int, () => []).add(row['item_name'] as String);
    }
    return [
      for (final r in rows)
        {
          ...r,
          'item_names': (namesByTxn[r['id']] ?? const []).join(', '),
        }
    ];
  }

  /// Normalized-name sale counts since [isoSince], excluding owner use.
  /// Names are matched via trim+lowercase because transaction_items stores
  /// denormalized display names.
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

  Future<Map<String, double>> getSalesSummarySince(String isoSince) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN is_owner_consumption = 0 THEN total_amount ELSE 0 END), 0) AS sales,
        COALESCE(SUM(CASE WHEN is_owner_consumption = 0 THEN paid_amount ELSE 0 END), 0) AS collected,
        COALESCE(SUM(CASE WHEN is_cash_sale = 1 THEN total_amount ELSE 0 END), 0) AS cash_sales,
        COALESCE(SUM(CASE WHEN is_owner_consumption = 1 THEN total_amount ELSE 0 END), 0) AS owner_use
      FROM transactions
      WHERE date >= ?
    ''', [isoSince]);
    final row = result.first;
    return {
      'sales': (row['sales'] as num).toDouble(),
      'collected': (row['collected'] as num).toDouble(),
      'owner_use': (row['owner_use'] as num).toDouble(),
    };
  }

  Future<List<Map<String, dynamic>>> getTopItemsSince(String isoSince, {int limit = 5}) async {
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

  Future<Map<String, dynamic>?> exportBackup() async {
    final db = await database;
    final items = await db.query('items');
    final customers = await db.query('customers');
    final transactions = await db.query('transactions');
    final transactionItems = await db.query('transaction_items');
    final dishes = await db.query('dishes');
    final dishIngredients = await db.query('dish_ingredients');
    final spoilageLog = await db.query('spoilage_log');
    final dishLeftovers = await db.query('dish_leftovers');
    return {
      'app': 'TalaKo',
      'version': 6,
      'exported_at': DateTime.now().toIso8601String(),
      'items': items,
      'customers': customers,
      'transactions': transactions,
      'transaction_items': transactionItems,
      'dishes': dishes,
      'dish_ingredients': dishIngredients,
      'spoilage_log': spoilageLog,
      'dish_leftovers': dishLeftovers,
    };
  }

  /// Accepts current TalaKo backups plus legacy ones from the pre-rename
  /// "Sari" v1 era (flat `credits` table instead of transactions).
  Future<void> importBackup(Map<String, dynamic> data) async {
    final appName = data['app']?.toString() ?? '';
    if (appName != 'TalaKo' && appName != 'Sari') {
      throw Exception('Not a valid TalaKo backup file');
    }
    if (!data.containsKey('transactions') &&
        !data.containsKey('credits') &&
        !data.containsKey('transaction_items')) {
      // Guard against restoring arbitrary JSON that would silently wipe
      // the live ledger.
      throw Exception('Backup contains no ledger data');
    }
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('dish_leftovers');
      await txn.delete('spoilage_log');
      await txn.delete('dish_ingredients');
      await txn.delete('dishes');
      await txn.delete('transaction_items');
      await txn.delete('transactions');
      await txn.delete('customers');
      await txn.delete('items');
      for (final item in (data['items'] as List)) {
        await txn.insert('items', item as Map<String, dynamic>);
      }
      for (final customer in (data['customers'] as List)) {
        await txn.insert('customers', customer as Map<String, dynamic>);
      }
      if (data.containsKey('transactions')) {
        for (final txnData in (data['transactions'] as List)) {
          await txn.insert('transactions', txnData as Map<String, dynamic>);
        }
      }
      if (data.containsKey('transaction_items')) {
        for (final item in (data['transaction_items'] as List)) {
          await txn.insert('transaction_items', item as Map<String, dynamic>);
        }
      }
      // Newer-format sections are optional so v2 backups still restore.
      if (data.containsKey('dishes')) {
        for (final dish in (data['dishes'] as List)) {
          await txn.insert('dishes', dish as Map<String, dynamic>);
        }
      }
      if (data.containsKey('dish_ingredients')) {
        for (final link in (data['dish_ingredients'] as List)) {
          await txn.insert('dish_ingredients', link as Map<String, dynamic>);
        }
      }
      if (data.containsKey('spoilage_log')) {
        for (final entry in (data['spoilage_log'] as List)) {
          await txn.insert('spoilage_log', entry as Map<String, dynamic>);
        }
      }
      // Legacy "Sari" v1 backups: flat credits table becomes one
      // transaction + line per credit, preserving paid amounts.
      if (!data.containsKey('transactions') && data.containsKey('credits')) {
        for (final c in (data['credits'] as List)) {
          final credit = c as Map<String, dynamic>;
          final total = (credit['total'] as num).toDouble();
          final paid = (credit['paid_amount'] as num).toDouble();
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
            'price': credit['price_per_unit'],
            'subtotal': total,
          });
        }
      }
      if (data.containsKey('dish_leftovers')) {
        for (final entry in (data['dish_leftovers'] as List)) {
          await txn.insert('dish_leftovers', entry as Map<String, dynamic>);
        }
      }
    });
  }
}