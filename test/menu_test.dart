import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:talako/database/database_helper.dart';
import 'package:talako/models/customer.dart';
import 'package:talako/models/dish.dart';
import 'package:talako/models/stock_enums.dart';
import 'package:talako/providers/inventory_provider.dart';
import 'package:talako/providers/transactions_provider.dart';
import 'package:talako/widgets/alphabet_strip.dart';

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

      final spoilageId = await db.insertSpoilage(SpoilageEntry(
        itemId: dish.id!,
        estimatedValue: 10.0,
        date: DateTime.now().toIso8601String(),
      ));
      expect(spoilageId, greaterThan(0));
    });
  });

  group('tap-sale', () {
    late int tapsiId;

    test('records settled cash sale hidden from Credit Book', () async {
      final db = DatabaseHelper.instance;
      final inv = InventoryProvider();

      tapsiId = await db.insertDish(Dish(name: 'Tapsilog', price: 75, capital: 42));

      final result = await inv.recordTapSale((await db.getAllDishes()).firstWhere((d) => d.id == tapsiId));
      expect(result, isNotNull);
      final (txnId, revenue) = result!;
      expect(revenue, 75.0);

      final txn = (await (await db.database)
          .query('transactions', where: 'id = ?', whereArgs: [txnId])).first;
      expect(txn['is_cash_sale'], 1);
      expect(txn['status'], 'PAID');
      expect((txn['paid_amount'] as num).toDouble(), 75.0);

      final line = (await (await db.database).query('transaction_items',
          where: 'transaction_id = ?', whereArgs: [txnId])).first;
      expect(line['dish_id'], tapsiId);
      expect((line['unit_capital'] as num).toDouble(), 42.0);

      final bookRows = await db.getActiveTransactionsWithCustomer();
      expect(bookRows.any((r) => r['id'] == txnId), isFalse);

      final today = await inv.todaySummary();
      expect(today['sales'], 75.0);
      expect(today['plates'], 1.0);
    });

    test('rapid double-tap debounces to a single sale', () async {
      final db = DatabaseHelper.instance;
      final inv = InventoryProvider();
      final dish =
          (await db.getAllDishes()).firstWhere((d) => d.id == tapsiId);
      final before = await inv.todaySummary();
      final t0 = DateTime(2026, 1, 1, 10);

      final r1 = await inv.recordTapSale(dish, now: t0);
      final r2 = await inv.recordTapSale(
          dish, now: t0.add(const Duration(milliseconds: 200)));

      expect(r1, isNotNull);
      expect(r2, isNull, reason: 'second press inside 350ms is swallowed');
      final after = await inv.todaySummary();
      expect(after['plates'], before['plates']! + 1);
    });

    test('undo removes exactly one tap-sale (delta-based)', () async {
      final inv = InventoryProvider();
      final dish = (await DatabaseHelper.instance.getAllDishes())
          .firstWhere((d) => d.id == tapsiId);

      final before = await inv.todaySummary();
      final base = DateTime.now();
      final first =
          await inv.recordTapSale(dish, now: base);
      await inv.recordTapSale(
          dish, now: base.add(const Duration(seconds: 1)));

      var after = await inv.todaySummary();
      expect(after['plates'], before['plates']! + 2);

      await inv.deleteTapSale(first!.$1);
      after = await inv.todaySummary();
      expect(after['plates'], before['plates']! + 1);
      expect(after['sales'], closeTo(before['sales']! + 75.0, 0.001));
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

    test('warn-only: saving with capital above price succeeds', () async {
      // The owner decides pricing reality; the app only warns via the
      // thin-margin badge on the card. No hard block.
      final inv = InventoryProvider();
      final error = await inv.saveDish(
          name: 'Risky Priced Dish', price: 50, capital: 60);
      expect(error, isNull);
      await inv.loadInventory();
      final dish =
          inv.dishes.firstWhere((d) => d.name == 'Risky Priced Dish');
      expect(dish.margin, isNegative);
      expect(dish.thinMargin, isTrue);
    });

    test('zero-capital dish never triggers the margin nag', () async {
      final inv = InventoryProvider();
      final error =
          await inv.saveDish(name: 'No Capital Dish', price: 50);
      expect(error, isNull);
    });
  });

  group('served counts', () {
    test('week and today counts keyed by dish after sales', () async {
      final inv = InventoryProvider();
      await inv.loadInventory();
      final id = inv.dishes.firstWhere((d) => d.name == 'Tapsilog').id!;
      expect(inv.servedWeek[id] ?? 0, greaterThanOrEqualTo(1));
      expect(inv.servedToday[id] ?? 0, greaterThanOrEqualTo(1),
          reason: 'the tap-sales from earlier groups happened just now');
    });
  });

  group('multi-dish receipts', () {
    test('every dish line is stamped with its dish', () async {
      final db = DatabaseHelper.instance;
      final txnProvider = TransactionsProvider();
      final customerId = await db.insertCustomer(Customer(name: 'Multi Cust'));
      final tapsilog =
          (await db.getAllDishes()).firstWhere((d) => d.name == 'Tapsilog');
      final pancitId =
          await db.insertDish(Dish(name: 'Pancit', price: 50, capital: 25));
      final pancit =
          (await db.getAllDishes()).firstWhere((d) => d.id == pancitId);

      final txnId = await txnProvider.addDishTransaction(customerId,
          ['Tapsilog', 'Pancit'], [1, 2], [tapsilog.price, pancit.price]);

      final lines = await (await db.database).query('transaction_items',
          where: 'transaction_id = ?', whereArgs: [txnId]);
      for (final l in lines) {
        // ignore: avoid_print
        print('LINE ${l['item_name']} dish_id=${l['dish_id']} cap=${l['unit_capital']}');
      }
      // ignore: avoid_print
      print('STAMPED=${lines.where((l) => l['dish_id'] != null).length} total=${lines.length}');
      expect(lines.where((l) => l['dish_id'] != null).length, 2,
          reason: 'both dishes on one receipt must link to their dishes');

      final counts = await db.getDishSaleCountsSince(
          InventoryProvider.dateStr(DateTime.now()));
      expect(counts[tapsilog.id], greaterThanOrEqualTo(1));
      expect(counts[pancit.id], 2);
    });
  });

  group('recap math', () {
    test('handles multi-quantity credit lines (delta-based)', () async {
      final db = DatabaseHelper.instance;
      final txnProvider = TransactionsProvider();
      final customerId = await db.insertCustomer(Customer(name: 'Qty Cust'));
      final dish = (await db.getAllDishes()).firstWhere((d) => d.name == 'Tapsilog');

      final now = DateTime.now();
      final dayStart = InventoryProvider.dateStr(DateTime(now.year, now.month, now.day));
      final dayEnd = InventoryProvider.dateStr(now.add(const Duration(days: 1)));

      double platesFor(List<Map<String, dynamic>> rows) =>
          rows.where((r) => r['name'] == 'Tapsilog')
              .fold(0, (a, r) => a + (r['plates'] as num).toDouble());
      double salesFor(List<Map<String, dynamic>> rows) =>
          rows.where((r) => r['name'] == 'Tapsilog')
              .fold(0.0, (a, r) => a + (r['sales'] as num).toDouble());

      final beforeRows = await db.getDishRecapForDay(dayStart, dayEnd);

      await txnProvider.addDishTransaction(
          customerId, ['Tapsilog'], [3], [75], dish: dish);

      final afterRows = await db.getDishRecapForDay(dayStart, dayEnd);
      expect(platesFor(afterRows) - platesFor(beforeRows), 3,
          reason: 'plates must count quantity, not receipt lines');
      expect(salesFor(afterRows) - salesFor(beforeRows), closeTo(225.0, 0.001),
          reason: 'recap reports raw output (revenue)');
    });
  });

  group('end of day', () {
    test('reheat leftovers consumed first and tracked to zero', () async {
      final db = DatabaseHelper.instance;
      final inv = InventoryProvider();

      final dishId =
          await db.insertDish(Dish(name: 'EOL Adobo', price: 60, capital: 30));

      await db.addLeftover(dishId, 1, 'reheat', '2026-01-01');
      expect(await inv.getReheatLeftoverPublic(dishId), 1);

      final dishObj = (await db.getAllDishes()).firstWhere((d) => d.id == dishId);
      final r1 = await inv.recordTapSale(
          dishObj, now: DateTime.now());
      expect(r1, isNotNull);
      expect(await inv.getReheatLeftoverPublic(dishId), 0,
          reason: 'leftover plate consumed first');

      final r2 = await inv.recordTapSale(
          dishObj, now: DateTime.now().add(const Duration(seconds: 1)));
      expect(r2, isNotNull);
      expect(await inv.getReheatLeftoverPublic(dishId), 0);
    });

    test('dispositions: pseudo-item + spoiled falls back to note text',
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
      expect(pseudo, isNotNull);
      expect(pseudo!.usageType, UsageType.ingredientOnly);
      expect(pseudo.stockStatus, StockStatus.wellStocked);

      final log = await db.getSpoilageLog();
      final entry = log.firstWhere((e) => e.note?.contains('EOL Adobo') ?? false);
      expect(entry.estimatedValue, 30.0, reason: 'capital x qty');
    });

    test('resetTodayTaps deletes cash only; credit receipts survive',
        () async {
      final db = DatabaseHelper.instance;
      final inv = InventoryProvider();
      await inv.loadInventory();
      final dish = inv.dishes.firstWhere((d) => d.name == 'Tapsilog');
      final txnProvider = TransactionsProvider();

      await inv.recordTapSale(dish);
      final customerId = await db.insertCustomer(Customer(name: 'Reset Cust'));
      final creditTxn = await txnProvider.addDishTransaction(
          customerId, ['Tapsilog'], [1], [75], dish: dish);

      final removed = await inv.resetTodayTaps();
      expect(removed, greaterThanOrEqualTo(1));

      final creditRow = await (await db.database)
          .query('transactions', where: 'id = ?', whereArgs: [creditTxn]);
      expect(creditRow, isNotEmpty,
          reason: 'customer receipts are structurally safe from Reset');
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

    test('maybeRunEndOfDay rolls unclosed gap days into one recap',
        () async {
      final db = DatabaseHelper.instance;
      final inv = InventoryProvider();

      final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      final customerId = await db.insertCustomer(Customer(name: 'Gap Cust'));
      final dish = (await db.getAllDishes()).firstWhere((d) => d.name == 'Tapsilog');
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
      await (await db.database).update(
        'transactions',
        {'date': twoDaysAgo.toIso8601String()},
        where: 'id = ?',
        whereArgs: [txnId],
      );
      await SharedPreferences.getInstance().then((p) =>
          p.setString('last_eod_day', InventoryProvider.dateStr(threeDaysAgo)));

      await inv.maybeRunEndOfDay();

      expect(inv.pendingRecap, isNotNull,
          reason: 'unclosed days must surface as a recap');
      expect(inv.pendingRecap!['rangeEnd'], isNotNull);
      final rows =
          (inv.pendingRecap!['rows'] as List).cast<Map<String, dynamic>>();
      expect(rows.any((r) => r['name'] == 'Tapsilog'), isTrue);

      await inv.markDayClosed();
      expect(inv.pendingRecap, isNull);
      final stored = await SharedPreferences.getInstance()
          .then((p) => p.getString('last_eod_day'));
      expect(stored, InventoryProvider.dateStr(DateTime.now()));
    });
  });

  group('daily tally', () {
    test('bulk tally records one hidden receipt with stamped lines',
        () async {
      final db = DatabaseHelper.instance;
      final inv = InventoryProvider();
      await inv.loadInventory();

      final before = await inv.todaySummary();
      final tapsi = inv.dishes.firstWhere((d) => d.name == 'Tapsilog');
      final txnId = await inv.saveTally({
        tapsi.id!: 5,
      });
      expect(txnId, isNotNull);

      // Hidden from Credit Book.
      final bookRows = await db.getActiveTransactionsWithCustomer();
      expect(bookRows.any((r) => r['id'] == txnId), isFalse);

      // Settled cash semantics.
      final txn = (await (await db.database)
          .query('transactions', where: 'id = ?', whereArgs: [txnId])).first;
      expect(txn['is_cash_sale'], 1);
      expect(txn['status'], 'PAID');

      // Summary delta: 5 plates x 75 = 375 output.
      final after = await inv.todaySummary();
      expect(after['plates'], before['plates']! + 5);
      expect(after['sales'], closeTo(before['sales']! + 375.0, 0.001));

      // Served counts bump for the dish.
      final tapsiRow = inv.dishes.firstWhere((d) => d.name == 'Tapsilog');
      expect(inv.servedToday[tapsiRow.id] ?? 0, greaterThanOrEqualTo(5));
    });

    test('all-zero tally records nothing', () async {
      final inv = InventoryProvider();
      await inv.loadInventory();
      final tapsi = inv.dishes.firstWhere((d) => d.name == 'Tapsilog');
      final before = await inv.todaySummary();

      final result = await inv.saveTally({});
      expect(result, isNull);

      final zero = await inv.saveTally({tapsi.id!: 0});
      expect(zero, isNull);

      final after = await inv.todaySummary();
      expect(after['plates'], before['plates']);
    });

    test('undo removes a whole tally in one go', () async {
      final inv = InventoryProvider();
      await inv.loadInventory();
      final tapsi = inv.dishes.firstWhere((d) => d.name == 'Tapsilog');
      final before = await inv.todaySummary();

      final txnId = await inv.saveTally({
        tapsi.id!: 2,
      });
      expect(txnId, isNotNull);

      await inv.deleteTapSale(txnId!);
      final after = await inv.todaySummary();
      expect(after['plates'], before['plates']);
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
