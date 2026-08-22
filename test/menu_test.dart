import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:talako/database/database_helper.dart';
import 'package:talako/models/customer.dart';
import 'package:talako/models/dish.dart';
import 'package:talako/models/stock_enums.dart';
import 'package:talako/providers/inventory_provider.dart';
import 'package:talako/providers/transactions_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Own database file: this suite runs in parallel with the others.
    DatabaseHelper.databaseName = 'talako_menu_test.db';
    final dbPath = await getDatabasesPath();
    await databaseFactory.deleteDatabase(join(dbPath, DatabaseHelper.databaseName));
  });

  group('schema v4 migration', () {
    test('v3 database upgrades cleanly and preserves rows', () async {
      final dbPath = await getDatabasesPath();
      final legacyPath = join(dbPath, DatabaseHelper.databaseName);

      // Simulate a v3 install (pre-Menu Inventory).
      final legacy = await databaseFactory.openDatabase(
        legacyPath,
        options: OpenDatabaseOptions(version: 3, onCreate: (db, v) async {
          await db.execute('''
            CREATE TABLE dishes (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT UNIQUE NOT NULL,
              price REAL NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
          await legacyTables(db);
        }),
      );
      await legacy.insert('dishes',
          {'name': 'Legacy Silog', 'price': 70.0, 'created_at': '2026-01-01T00:00:00.000'});
      await legacy.close();

      final db = DatabaseHelper.instance;
      final dish = await db.getDishById((await db.getAllDishes()).first.id!);
      expect(dish!.name, 'Legacy Silog');
      expect(dish.capital, 0.0, reason: 'v3 rows get capital default');
    });
  });

  group('tap-sale', () {
    late Dish tapsi;

    test('records settled cash sale hidden from Credit Book', () async {
      final db = DatabaseHelper.instance;
      final inv = InventoryProvider();

      final id = await db.insertDish(Dish(name: 'Tapsilog', price: 75, capital: 42));
      tapsi = (await db.getAllDishes()).firstWhere((d) => d.id == id);

      final result = await inv.recordTapSale(tapsi);
      expect(result, isNotNull);
      final (txnId, margin) = result!;
      expect(margin, 33.0);

      // Settled instantly - never surfaces as debt even without flags.
      final txn = (await (await db.database)
          .query('transactions', where: 'id = ?', whereArgs: [txnId])).first;
      expect(txn['is_cash_sale'], 1);
      expect(txn['status'], 'PAID');
      expect((txn['paid_amount'] as num).toDouble(), 75.0);

      final line = (await (await db.database).query('transaction_items',
          where: 'transaction_id = ?', whereArgs: [txnId])).first;
      expect(line['dish_id'], id);
      expect((line['unit_capital'] as num).toDouble(), 42.0);

      // Hidden from every credit-book view.
      final bookRows = await db.getActiveTransactionsWithCustomer();
      expect(bookRows.any((r) => r['id'] == txnId), isFalse);

      // But counted in the Menu summary.
      final today = await inv.todaySummary();
      expect(today['sales'], 75.0);
      expect(today['profit'], 33.0);
      expect(today['plates'], 1.0);
    });

    test('undo removes exactly one tap-sale', () async {
      final inv = InventoryProvider();
      final before = await inv.todaySummary();

      final first = await inv.recordTapSale(tapsi);
      await inv.recordTapSale(tapsi);

      var after = await inv.todaySummary();
      expect(after['plates'], before['plates']! + 2);

      await inv.deleteTapSale(first!.$1);
      after = await inv.todaySummary();
      expect(after['plates'], before['plates']! + 1);
      expect(after['profit'], closeTo(before['profit']! + 33.0, 0.001));
    });

    test('credit dish lines count toward Today; plain items do not', () async {
      final db = DatabaseHelper.instance;
      final inv = InventoryProvider();
      final txnProvider = TransactionsProvider();

      final before = await inv.todaySummary();
      final customerId = await db.insertCustomer(Customer(name: 'Menu Cust'));

      await txnProvider.addDishTransaction(
          customerId, ['Tapsilog'], [2], [75],
          dish: tapsi, deductIngredients: false);
      await txnProvider.addTransactionWithItemNames(
          customerId, ['Plain Chips'], [1], [20]);

      final after = await inv.todaySummary();
      expect(after['plates'], before['plates']! + 2,
          reason: '2 credit silog; plain non-dish items never count');
      expect(after['profit'], closeTo(before['profit']! + 66.0, 0.001),
          reason: 'credit line margin uses stamped unit_capital');

      // deducted_ingredients flag written on the credit transaction.
      final flagged = await (await db.database)
          .query('transactions', where: 'deducted_ingredients = 1');
      expect(flagged, isEmpty, reason: 'deduction was disabled for this sale');
    });
  });

  group('margin math', () {
    test('per-plate margin and thin-margin badge', () {
      final healthy = Dish(name: 'A', price: 75, capital: 42);
      expect(healthy.margin, 33.0);
      expect(healthy.thinMargin, isFalse);

      final thin = Dish(name: 'B', price: 25, capital: 22);
      expect(thin.margin, 3.0);
      expect(thin.marginRate, closeTo(0.12, 0.001));
      expect(thin.thinMargin, isTrue);

      final noCapital = Dish(name: 'C', price: 50);
      expect(noCapital.thinMargin, isFalse,
          reason: 'no puhunan entered yet - do not nag');
    });

    test('saveDish rejects puhunan above selling price', () async {
      final inv = InventoryProvider();
      final error = await inv.saveDish(
          name: 'Bad Margin Dish', price: 50, capital: 60, ingredientIds: []);
      expect(error, 'Puhunan must be below the selling price');
    });
  });

  group('served counts & availability', () {
    test('week counts keyed by dish after sales', () async {
      final inv = InventoryProvider();
      await inv.loadInventory();
      final id = inv.dishes.firstWhere((d) => d.dish.name == 'Tapsilog').dish.id!;
      expect(inv.servedWeek[id] ?? 0, greaterThanOrEqualTo(3));
    });

    test('empty-ingredient dish stays unavailable', () {
      final d = DishWithIngredients(dish: Dish(name: 'X', price: 1));
      expect(d.availability, DishAvailability.unavailable);
    });
  });
}

/// Tables a v3 install already had besides `dishes`.
Future<void> legacyTables(dynamic db) async {
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
}
