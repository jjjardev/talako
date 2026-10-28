import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:talako/database/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late String dbPath;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.databaseName = 'talako_migration_v7_test.db';
    dbPath = join(await getDatabasesPath(), DatabaseHelper.databaseName);
    await databaseFactory.deleteDatabase(dbPath);
  });

  test('v6 database migrates to v7 money, owner-use, and item links',
      () async {
    final legacy = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, version) async {
          await db.execute('PRAGMA user_version = 6');
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
              UNIQUE(dish_id, item_id)
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
        },
      ),
    );

    await legacy.insert('items', {
      'id': 1,
      'name': 'Coke',
      'price': 25.50,
      'created_at': '2026-01-01T00:00:00',
    });
    await legacy.insert('customers', {
      'id': 1,
      'name': 'Maria',
      'created_at': '2026-01-01T00:00:00',
    });
    await legacy.insert('customers', {
      'id': 2,
      'name': 'Personal Use',
      'created_at': '2026-01-01T00:00:00',
    });
    await legacy.insert('transactions', {
      'id': 1,
      'customer_id': 1,
      'date': '2026-01-02T00:00:00',
      'total_amount': 51.00,
      'paid_amount': 10.00,
      'status': 'ACTIVE',
    });
    await legacy.insert('transactions', {
      'id': 2,
      'customer_id': 2,
      'date': '2026-01-03T00:00:00',
      'total_amount': 25.50,
      'paid_amount': 0.0,
      'status': 'ACTIVE',
      'is_owner_consumption': 1,
    });
    await legacy.insert('transaction_items', {
      'id': 1,
      'transaction_id': 1,
      'item_name': 'Coke',
      'quantity': 2,
      'price': 25.50,
      'subtotal': 51.00,
    });
    await legacy.insert('transaction_items', {
      'id': 2,
      'transaction_id': 2,
      'item_name': 'Coke',
      'quantity': 1,
      'price': 25.50,
      'subtotal': 25.50,
    });
    await legacy.insert('spoilage_log', {
      'id': 1,
      'item_id': 1,
      'estimated_value': 25.50,
      'note': 'old',
      'date': '2026-01-04T00:00:00',
    });
    await legacy.close();

    final db = DatabaseHelper.instance;
    final items = await db.getAllItems();
    expect(items.single.price, 2550);
    expect(await db.getCustomerByName('Personal Use'), isNull);

    final txns = await (await db.database).query('transactions', orderBy: 'id');
    expect((txns[0]['total_amount'] as num).toInt(), 5100);
    expect((txns[0]['paid_amount'] as num).toInt(), 1000);
    expect(txns[1]['customer_id'], isNull);
    expect(txns[1]['is_owner_consumption'], 1);

    final lines =
        await (await db.database).query('transaction_items', orderBy: 'id');
    expect(lines[0]['item_id'], 1);
    expect((lines[0]['price'] as num).toInt(), 2550);
    expect((lines[0]['subtotal'] as num).toInt(), 5100);

    final spoilage = await (await db.database).query('spoilage_log');
    expect((spoilage.single['estimated_value'] as num).toInt(), 2550);

    final version = await (await db.database).getVersion();
    expect(version, 7);

    final dir = Directory(dirname(dbPath));
    final backups = await dir
        .list()
        .where((e) =>
            e.path.contains('pre_v7_') && e.path.endsWith('.db'))
        .toList();
    expect(backups, isNotEmpty,
        reason: 'migration must leave a pre-v7 recovery copy');
    await db.close();
  });
}
