import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:path/path.dart';
import '../models/item.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../models/transaction_item.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  Database? _database;
  Future<void>? _initFuture;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    if (_initFuture == null) {
      _initFuture = _initDB('talako.db').then((db) => _database = db);
    }
    await _initFuture;
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);
    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        price REAL NOT NULL,
        created_at TEXT NOT NULL
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
  }

  Future<String> getDbFilePath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, 'talako.db');
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      _initFuture = null;
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

  Future<int> insertTransaction(Transaction transaction) async {
    final db = await database;
    return await db.insert('transactions', transaction.toMap());
  }

  Future<List<Transaction>> getActiveTransactions() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT * FROM transactions
      WHERE status = 'ACTIVE' AND paid_amount < total_amount
      ORDER BY date ASC
    ''');
    return result.map((map) => Transaction.fromMap(map)).toList();
  }

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
      where: 'customer_id = ? AND status = ? AND paid_amount < total_amount',
      whereArgs: [customerId, 'ACTIVE'],
      orderBy: 'date ASC',
    );
    return result.map((map) => Transaction.fromMap(map)).toList();
  }

  Future<List<Transaction>> getPaidTransactionsByCustomer(int customerId) async {
    final db = await database;
    final result = await db.query(
      'transactions',
      where: 'customer_id = ? AND (status = ? OR paid_amount >= total_amount)',
      whereArgs: [customerId, 'PAID'],
      orderBy: 'date DESC',
    );
    return result.map((map) => Transaction.fromMap(map)).toList();
  }

  Future<double> getCustomerOutstandingBalance(int customerId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(total_amount - paid_amount), 0) as balance FROM transactions WHERE customer_id = ? AND paid_amount < total_amount',
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
      WHERE t.paid_amount < t.total_amount
      GROUP BY c.id
      HAVING balance > 0
    ''');
  }

  Future<Set<int>> getAllOverdueCustomerIds() async {
    final db = await database;
    final cutoff = DateTime.now().subtract(const Duration(days: 14)).toIso8601String();
    final result = await db.rawQuery(
      'SELECT DISTINCT customer_id FROM transactions WHERE paid_amount < total_amount AND date < ?',
      [cutoff],
    );
    return result.map((row) => row['customer_id'] as int).toSet();
  }

  Future<bool> hasOverdueTransactions(int customerId) async {
    final db = await database;
    final cutoff = DateTime.now().subtract(const Duration(days: 14)).toIso8601String();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM transactions WHERE customer_id = ? AND paid_amount < total_amount AND date < ?',
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
        SELECT DISTINCT customer_id FROM transactions WHERE paid_amount < total_amount
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
    final status = newPaidAmount >= total ? 'PAID' : 'ACTIVE';
    return await db.update(
      'transactions',
      {'paid_amount': newPaidAmount, 'status': status},
      where: 'id = ?',
      whereArgs: [transactionId],
    );
  }

  Future<List<Map<String, dynamic>>> getOverdueTransactions() async {
    final db = await database;
    final cutoff = DateTime.now().subtract(const Duration(days: 14)).toIso8601String();
    return await db.rawQuery('''
      SELECT t.*, c.name as customer_name
      FROM transactions t
      INNER JOIN customers c ON c.id = t.customer_id
      WHERE t.paid_amount < t.total_amount AND t.date < ?
      ORDER BY t.date ASC
    ''', [cutoff]);
  }

  Future<List<Map<String, dynamic>>> getActiveTransactionsWithCustomer() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT t.*, c.name as customer_name,
        COALESCE(GROUP_CONCAT(ti.item_name), '') as item_names,
        COALESCE(GROUP_CONCAT(ti.quantity), '') as item_qtys,
        COALESCE(GROUP_CONCAT(ti.price), '') as item_prices,
        COALESCE(GROUP_CONCAT(ti.subtotal), '') as item_subtotals
      FROM transactions t
      INNER JOIN customers c ON c.id = t.customer_id
      LEFT JOIN transaction_items ti ON ti.transaction_id = t.id
      WHERE t.paid_amount < t.total_amount
      GROUP BY t.id
      ORDER BY t.date ASC
    ''');
  }

  // ─── Transaction Items ──────────────────────────────────────────────

  Future<int> insertTransactionItem(TransactionItem item) async {
    final db = await database;
    return await db.insert('transaction_items', item.toMap());
  }

  Future<void> insertTransactionWithItems(int customerId, List<Map<String, dynamic>> items) async {
    final db = await database;
    final date = DateTime.now().toIso8601String();
    double totalAmount = 0;
    for (final item in items) {
      totalAmount += (item['subtotal'] as num).toDouble();
    }
    await db.transaction((txn) async {
      final txnId = await txn.insert('transactions', {
        'customer_id': customerId,
        'date': date,
        'total_amount': totalAmount,
        'paid_amount': 0,
        'status': 'ACTIVE',
      });
      for (final item in items) {
        await txn.insert('transaction_items', {
          'transaction_id': txnId,
          'item_name': item['item_name'],
          'quantity': item['quantity'],
          'price': item['price'],
          'subtotal': item['subtotal'],
        });
      }
    });
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

  Future<int> getActiveTransactionCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM transactions WHERE paid_amount < total_amount',
    );
    return (result.first['cnt'] as int);
  }

  // ─── Backup & Restore ───────────────────────────────────────────────

  Future<Map<String, dynamic>?> exportBackup() async {
    final db = await database;
    final items = await db.query('items');
    final customers = await db.query('customers');
    final transactions = await db.query('transactions');
    final transactionItems = await db.query('transaction_items');
    return {
      'app': 'TalaKo',
      'version': 2,
      'exported_at': DateTime.now().toIso8601String(),
      'items': items,
      'customers': customers,
      'transactions': transactions,
      'transaction_items': transactionItems,
    };
  }

  Future<void> importBackup(Map<String, dynamic> data) async {
    if (data['app'] != 'TalaKo') {
      throw Exception('Not a valid TalaKo backup file');
    }
    final db = await database;
    await db.transaction((txn) async {
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
    });
  }
}