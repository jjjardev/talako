import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:talako/database/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talako/models/customer.dart';
import 'package:talako/models/dish.dart';
import 'package:talako/models/stock_enums.dart';
import 'package:talako/widgets/alphabet_strip.dart';
import 'package:talako/providers/inventory_provider.dart';
import 'package:talako/providers/transactions_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

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
      // ignore: avoid_print
      print('CHK tap-sale: dishes=${(await db.getAllDishes()).length}');
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
          customerId, ['Tapsilog'], [2], [75], dish: tapsi);
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
      final error =
          await inv.saveDish(name: 'Bad Margin Dish', price: 50, capital: 60);
      expect(error, 'Puhunan must be below the selling price');
    });
  });

  group('served counts', () {
    test('week and today counts keyed by dish after sales', () async {
      final inv = InventoryProvider();
      await inv.loadInventory();
      final id = inv.dishes.firstWhere((d) => d.name == 'Tapsilog').id!;
      expect(inv.servedWeek[id] ?? 0, greaterThanOrEqualTo(3));
      expect(inv.servedToday[id] ?? 0, greaterThanOrEqualTo(1),
          reason: 'the credit sale from earlier groups happened just now');
    });
  });
group('end of day', () {
  test('reheat leftovers are consumed first and tracked to zero',
      () async {
    final db = DatabaseHelper.instance;
    final inv = InventoryProvider();

    final dishId =
        await db.insertDish(Dish(name: 'EOL Adobo', price: 60, capital: 30));

    // Yesterday's unsold plate marked for reheat.
    await db.addLeftover(dishId, 1, 'reheat', '2026-01-01');
    expect(await inv.getReheatLeftoverPublic(dishId), 1);

    final dishObj = (await db.getAllDishes()).firstWhere((d) => d.id == dishId);

    // First sale consumes the leftover.
    final r1 = await inv.recordTapSale(dishObj);
    expect(r1, isNotNull);
    expect(await inv.getReheatLeftoverPublic(dishId), 0);

    // Second sale still records normally.
    final r2 = await inv.recordTapSale(dishObj);
    expect(r2, isNotNull);
    expect((await inv.todaySummary())['plates'], greaterThanOrEqualTo(2));
  });

  test('recap math handles multi-quantity credit lines', () async {
    final db = DatabaseHelper.instance;
    final txnProvider = TransactionsProvider();
    final customerId = await db.insertCustomer(Customer(name: 'Qty Cust'));
    final dish = (await db.getAllDishes()).firstWhere((d) => d.name == 'Tapsilog');

    final now = DateTime.now();
    final dayStart =
        InventoryProvider.dateStr(DateTime(now.year, now.month, now.day));
    final dayEnd = InventoryProvider.dateStr(now.add(const Duration(days: 1)));

    double platesFor(List<Map<String, dynamic>> rows) =>
        rows.where((r) => r['name'] == 'Tapsilog')
            .fold(0, (a, r) => a + (r['plates'] as num).toDouble());
    double profitFor(List<Map<String, dynamic>> rows) =>
        rows.where((r) => r['name'] == 'Tapsilog')
            .fold(0.0, (a, r) => a + (r['profit'] as num).toDouble());

    final beforeRows = await db.getDishRecapForDay(dayStart, dayEnd);

    await txnProvider.addDishTransaction(
        customerId, ['Tapsilog'], [3], [75], dish: dish);

    final afterRows = await db.getDishRecapForDay(dayStart, dayEnd);
    expect(platesFor(afterRows) - platesFor(beforeRows), 3,
        reason: 'plates must count quantity, not receipt lines');
    expect(profitFor(afterRows) - profitFor(beforeRows), closeTo(99.0, 0.001),
        reason: 'profit = (price - capital) x quantity');
  });

  test('dispositions: ingredient pseudo-item + spoiled->spoilage log',
      () async {
    final db = DatabaseHelper.instance;
    final inv = InventoryProvider();
    await inv.loadInventory();
    final dish = inv.dishes.firstWhere((d) => d.name == 'EOL Adobo');

    await inv.saveLeftovers([
      (dishId: dish.id!, qty: 2, disposition: 'ingredients'),
      (dishId: dish.id!, qty: 1, disposition: 'spoiled'),
    ]);

    final pseudo = await db.getItemByName('Leftover: EOL Adobo');
    expect(pseudo, isNotNull,
        reason: 'ingredient conversion creates a usable pseudo-item');
    expect(pseudo!.usageType, UsageType.ingredientOnly);
    expect(pseudo.stockStatus, StockStatus.wellStocked);

    final monthStart =
        DateTime(DateTime.now().year, DateTime.now().month).toIso8601String();
    final spoilage = await db.spoilageTotalSince(monthStart);
    expect(spoilage, greaterThanOrEqualTo(30.0),
        reason: 'waste valued at capital x qty');
  });

  test('resetTodayTaps deletes cash only; credit receipts survive', () async {
    final db = DatabaseHelper.instance;
    final inv = InventoryProvider();
    final txnProvider = TransactionsProvider();
    await inv.loadInventory();
    final dish = inv.dishes.firstWhere((d) => d.name == 'Tapsilog');

    await inv.recordTapSale(dish);
    final customerId = await db.insertCustomer(Customer(name: 'Reset Cust'));
    final creditTxn = await txnProvider.addDishTransaction(
        customerId, ['Tapsilog'], [1], [75], dish: dish);

    final removed = await inv.resetTodayTaps();
    expect(removed, greaterThanOrEqualTo(1));

    final creditRow = (await (await db.database)
        .query('transactions', where: 'id = ?', whereArgs: [creditTxn]));
    expect(creditRow, isNotEmpty,
        reason: 'customer receipts are structurally safe from Reset');
  });

  test('maybeRunEndOfDay rolls unclosed gap days into one recap', () async {
    final db = DatabaseHelper.instance;
    final inv = InventoryProvider();

    // Simulate: last closed 3 days ago, sale happened 2 days ago.
    final threeDaysAgo =
        DateTime.now().subtract(const Duration(days: 3));
    final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
    final customerId = await db.insertCustomer(Customer(name: 'Gap Cust'));
    final all = await db.getAllDishes();
    final dish = all.firstWhere(
      (d) => d.name == 'Tapsilog',
      orElse: () => throw StateError(
          'Tapsilog missing; dishes present: ${all.map((d) => d.name).toList()}'),
    );
    final txnId = await db.insertTransactionWithItems(customerId, [
      {
        'item_name': 'Tapsilog',
        'quantity': 1,
        'price': dish.price,
        'subtotal': dish.price,
        'dish_id': dish.id,
        'unit_capital': dish.capital,
      }
    ], isCashSale: true, dishId: dish.id);
    assert(dish.id != null);
    await (await db.database).update(
      'transactions',
      {'date': twoDaysAgo.toIso8601String()},
      where: 'id = ?',
      whereArgs: [txnId],
    );
    final check = await (await db.database).query('transactions',
        where: 'id = ?', whereArgs: [txnId]);
    // ignore: avoid_print
    print('CHK gap txn: ${check.isNotEmpty ? check.first : 'MISSING'}');

    await SharedPreferences.getInstance().then((p) =>
        p.setString('last_eod_day', InventoryProvider.dateStr(threeDaysAgo)));
    // ignore: avoid_print
    print('CHK stored=${(await SharedPreferences.getInstance()).getString('last_eod_day')}');

    final direct = await db.getDishRecapForDay(
        InventoryProvider.dateStr(threeDaysAgo), InventoryProvider.dateStr(DateTime.now()));
    // ignore: avoid_print
    print('CHK direct=${direct.length} rows=${direct.isNotEmpty ? direct.first : '-'}');
    await inv.maybeRunEndOfDay();
    // ignore: avoid_print
    print('CHK pending=${inv.pendingRecap != null ? inv.pendingRecap!['day'] : 'null'}');

    expect(inv.pendingRecap, isNotNull,
        reason: 'unclosed days must surface as a recap');
    expect(inv.pendingRecap!['rangeEnd'], isNotNull,
        reason: 'multi-day gaps expose an end date');
    final rows = (inv.pendingRecap!['rows'] as List).cast<Map<String, dynamic>>();
    expect(rows.any((r) => r['name'] == 'Tapsilog'), isTrue);

    await inv.markDayClosed();
    expect(inv.pendingRecap, isNull);
    final stored =
        await SharedPreferences.getInstance().then((p) => p.getString('last_eod_day'));
    expect(stored, InventoryProvider.dateStr(DateTime.now()));
  });

  test('undoLastTapSale works without in-memory history', () async {
    final inv = InventoryProvider();
    await inv.loadInventory();
    final dish = inv.dishes.firstWhere((d) => d.name == 'Tapsilog');
    await inv.recordTapSale(dish);
    final before = await inv.todaySummary();

    final ok = await inv.undoLastTapSale();
    expect(ok, isTrue, reason: 'falls back to querying the latest tap');
    final after = await inv.todaySummary();
    expect(after['plates']!, lessThan(before['plates']! + 1));
  });
});

group('alphabet index', () {
  test('letterOffsets maps first occurrence and buckets symbols', () {
    final offsets = AlphabetStrip.letterOffsets(
        ['banana', 'Apple', 'chips', 'avocado', '1sachet']);
    expect(offsets['A'], 1);
    expect(offsets['B'], 0);
    expect(offsets['C'], 2);
    expect(offsets['#'], 4);
    expect(offsets.containsKey('D'), isFalse);
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

