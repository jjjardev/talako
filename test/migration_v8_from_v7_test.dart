import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:talako/database/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.databaseName = 'talako_migration_v8_from_v7_test.db';
    final path = join(await getDatabasesPath(), DatabaseHelper.databaseName);
    await databaseFactory.deleteDatabase(path);
  });

  test('v7 database migrates in place to v8', () async {
    final path = join(await getDatabasesPath(), DatabaseHelper.databaseName);
    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 7,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE items (
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
            CREATE TABLE customers (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE transactions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              customer_id INTEGER,
              date TEXT NOT NULL,
              total_amount INTEGER NOT NULL DEFAULT 0,
              paid_amount INTEGER NOT NULL DEFAULT 0,
              status TEXT NOT NULL DEFAULT 'ACTIVE',
              is_owner_consumption INTEGER NOT NULL DEFAULT 0,
              is_cash_sale INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE transaction_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              transaction_id INTEGER NOT NULL,
              item_id INTEGER,
              item_name TEXT NOT NULL,
              quantity INTEGER NOT NULL DEFAULT 1,
              price INTEGER NOT NULL DEFAULT 0,
              subtotal INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE spoilage_log (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              item_id INTEGER,
              estimated_value INTEGER NOT NULL DEFAULT 0,
              note TEXT,
              date TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    await legacy.insert('customers', {
      'id': 1,
      'name': 'V7 Maria',
      'created_at': '2026-01-01T00:00:00',
    });
    await legacy.insert('transactions', {
      'id': 1,
      'customer_id': 1,
      'date': '2026-01-02T00:00:00',
      'total_amount': 1500,
      'paid_amount': 0,
      'status': 'ACTIVE',
    });
    await legacy.close();

    final db = DatabaseHelper.instance;
    final row = (await (await db.database)
            .query('transactions', where: 'id = ?', whereArgs: [1]))
        .first;
    expect((await (await db.database).getVersion()), 8);
    expect((row['total_amount'] as num).toInt(), 1500);
    expect(row['transcribed_to_book'], 0);
    expect(row['transcribed_at'], isNull);

    final indexes = await (await db.database)
        .rawQuery("PRAGMA index_list('transactions')");
    expect(indexes.any((i) => i['name'] == 'idx_txn_transcribed'), isTrue);
    await db.close();
  });
}
