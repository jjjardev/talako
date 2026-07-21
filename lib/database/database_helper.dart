import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/item.dart';
import '../models/customer.dart';
import '../models/credit_entry.dart';

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
    return await openDatabase(path, version: 1, onCreate: _createDB);
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
      CREATE TABLE credits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        item_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        price_per_unit REAL NOT NULL,
        total REAL NOT NULL,
        paid_amount REAL NOT NULL DEFAULT 0,
        timestamp TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');
  }

  Future<String> getDbFilePath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, 'talako.db');
  }

  Future<void> close() async {
    if (_database != null) {
      _database!.close();
      _database = null;
      _initFuture = null;
    }
  }

  // Items
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

  // Customers
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

  // Credits
  Future<int> insertCredit(CreditEntry credit) async {
    final db = await database;
    return await db.insert('credits', credit.toMap());
  }

  Future<List<CreditEntry>> getCreditsByCustomer(int customerId) async {
    final db = await database;
    final result = await db.query(
      'credits',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'timestamp DESC',
    );
    return result.map((map) => CreditEntry.fromMap(map)).toList();
  }

  Future<List<CreditEntry>> getUnsettledCreditsByCustomer(int customerId) async {
    final db = await database;
    final result = await db.query(
      'credits',
      where: 'customer_id = ? AND paid_amount < total',
      whereArgs: [customerId],
      orderBy: 'timestamp DESC',
    );
    return result.map((map) => CreditEntry.fromMap(map)).toList();
  }

  Future<List<CreditEntry>> getSettledCreditsByCustomer(int customerId) async {
    final db = await database;
    final result = await db.query(
      'credits',
      where: 'customer_id = ? AND paid_amount >= total',
      whereArgs: [customerId],
      orderBy: 'timestamp DESC',
    );
    return result.map((map) => CreditEntry.fromMap(map)).toList();
  }

  Future<double> getOutstandingBalance(int customerId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(total - paid_amount), 0) as balance FROM credits WHERE customer_id = ? AND paid_amount < total',
      [customerId],
    );
    return (result.first['balance'] as num).toDouble();
  }

  Future<List<Map<String, dynamic>>> getCustomersWithBalances() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT c.id, c.name, c.created_at,
        COALESCE(SUM(cr.total - cr.paid_amount), 0) as balance
      FROM customers c
      INNER JOIN credits cr ON cr.customer_id = c.id
      WHERE cr.paid_amount < cr.total
      GROUP BY c.id
      HAVING balance > 0
    ''');
  }

  Future<Set<int>> getAllOverdueCustomerIds() async {
    final db = await database;
    final cutoff = DateTime.now().subtract(const Duration(days: 14)).toIso8601String();
    final result = await db.rawQuery(
      'SELECT DISTINCT customer_id FROM credits WHERE paid_amount < total AND timestamp < ?',
      [cutoff],
    );
    return result.map((row) => row['customer_id'] as int).toSet();
  }

  Future<List<Map<String, dynamic>>> getSettledCustomers() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT c.id, c.name, c.created_at, MAX(cr.timestamp) as last_cleared
      FROM customers c
      INNER JOIN credits cr ON cr.customer_id = c.id
      WHERE c.id NOT IN (
        SELECT DISTINCT customer_id FROM credits WHERE paid_amount < total
      )
      GROUP BY c.id
      ORDER BY last_cleared DESC
    ''');
  }

  Future<bool> hasOverdueCredits(int customerId) async {
    final db = await database;
    final cutoff = DateTime.now().subtract(const Duration(days: 14)).toIso8601String();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM credits WHERE customer_id = ? AND paid_amount < total AND timestamp < ?',
      [customerId, cutoff],
    );
    return (result.first['cnt'] as int) > 0;
  }

  Future<int> updateCreditPaidAmount(int creditId, double newPaidAmount) async {
    final db = await database;
    return await db.update(
      'credits',
      {'paid_amount': newPaidAmount},
      where: 'id = ?',
      whereArgs: [creditId],
    );
  }

  Future<List<CreditEntry>> getAllCredits() async {
    final db = await database;
    final result = await db.query('credits', orderBy: 'timestamp DESC');
    return result.map((map) => CreditEntry.fromMap(map)).toList();
  }

  Future<Map<String, dynamic>?> exportBackup() async {
    final db = await database;
    final items = await db.query('items');
    final customers = await db.query('customers');
    final credits = await db.query('credits');
    return {
      'app': 'TalaKo',
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'items': items,
      'customers': customers,
      'credits': credits,
    };
  }

  Future<void> importBackup(Map<String, dynamic> data) async {
    if (data['app'] != 'TalaKo') {
      throw Exception('Not a valid TalaKo backup file');
    }
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('credits');
      await txn.delete('customers');
      await txn.delete('items');
      for (final item in (data['items'] as List)) {
        await txn.insert('items', item as Map<String, dynamic>);
      }
      for (final customer in (data['customers'] as List)) {
        await txn.insert('customers', customer as Map<String, dynamic>);
      }
      for (final credit in (data['credits'] as List)) {
        await txn.insert('credits', credit as Map<String, dynamic>);
      }
    });
  }
}
