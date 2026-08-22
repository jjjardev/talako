import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:talako/database/database_helper.dart';
import 'package:talako/models/customer.dart';
import 'package:talako/models/dish.dart';
import 'package:talako/models/item.dart';
import 'package:talako/models/stock_enums.dart';
import 'package:talako/providers/inventory_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Isolate this suite's database from other test files running in parallel.
    DatabaseHelper.databaseName = 'talako_inventory_test.db';
    final dbPath = await getDatabasesPath();
    await databaseFactory.deleteDatabase(join(dbPath, 'talako_inventory_test.db'));
  });

  group('schema v3 migration', () {
    test('v2 database upgrades cleanly and preserves rows', () async {
      final dbPath = await getDatabasesPath();
      final legacyPath = join(dbPath, DatabaseHelper.databaseName);

      // Simulate an old v2 install.
      final legacy = await databaseFactory.openDatabase(
        legacyPath,
        options: OpenDatabaseOptions(version: 2, onCreate: (db, v) async {
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
        }),
      );
      await legacy.insert('items',
          {'name': 'Legacy Coke', 'price': 40.0, 'created_at': '2026-01-01T00:00:00.000'});
      await legacy.close();

      // Opening through the helper must trigger v2 -> v3.
      final db = DatabaseHelper.instance;
      final migrated = await db.getItemByName('Legacy Coke');
      expect(migrated, isNotNull);
      expect(migrated!.stockStatus, StockStatus.wellStocked);
      expect(migrated.usageType, UsageType.retailOnly);

      // New tables exist and are usable.
      final dishId = await db.insertDish(Dish(name: 'Migration Dish', price: 50));
      expect(dishId, greaterThan(0));
      final spoilageId = await db.insertSpoilage(SpoilageEntry(
        itemId: migrated.id!,
        estimatedValue: 10.0,
        date: DateTime.now().toIso8601String(),
      ));
      expect(spoilageId, greaterThan(0));
    });
  });

  group('stock & freshness', () {
    test('cycling stock status persists', () async {
      final db = DatabaseHelper.instance;
      final item = await db.insertItem(Item(name: 'Cycle Chips', price: 20));
      await db.updateItemStockStatus(item, StockStatus.runningLow.dbValue);
      var loaded = (await db.getAllItems()).firstWhere((i) => i.name == 'Cycle Chips');
      expect(loaded.stockStatus, StockStatus.runningLow);
      expect(loaded.lastStatusUpdated, isNotNull);

      await db.updateItemStockStatus(item, StockStatus.outOfStock.dbValue);
      loaded = (await db.getAllItems()).firstWhere((i) => i.name == 'Cycle Chips');
      expect(loaded.stockStatus, StockStatus.outOfStock);
    });

    test('restock resets both statuses and stamps time', () async {
      final db = DatabaseHelper.instance;
      final a = await db.insertItem(Item(
        name: 'Restock Eggs',
        price: 9,
        stockStatus: StockStatus.outOfStock,
        freshnessStatus: FreshnessStatus.emptySpoiled,
        usageType: UsageType.both,
      ));
      await db.markItemsRestocked([a]);
      final loaded = (await db.getAllItems()).firstWhere((i) => i.id == a);
      expect(loaded.stockStatus, StockStatus.wellStocked);
      expect(loaded.freshnessStatus, FreshnessStatus.fresh);
      expect(loaded.lastRestocked, isNotNull);
    });
  });

  group('dishes', () {
    late int eggId, riceId, porkId;

    test('CRUD + ingredient stitching', () async {
      final db = DatabaseHelper.instance;
      eggId = await db.insertItem(
          Item(name: 'Dish Egg', price: 9, usageType: UsageType.both));
      riceId = await db.insertItem(Item(
          name: 'Dish Rice', price: 12, usageType: UsageType.both));
      porkId = await db.insertItem(Item(
          name: 'Dish Pork', price: 45, usageType: UsageType.ingredientOnly));

      final tapsi = await db.insertDish(Dish(name: 'Tapsilog', price: 75));
      await db.setDishIngredients(tapsi, [eggId, riceId, porkId]);

      final map = await db.getIngredientsForDishes([tapsi]);
      expect(map[tapsi]!.length, 3);
      expect(map[tapsi]!.any((i) => i.name == 'Dish Egg'), isTrue);

      // Re-setting replaces (no duplicates).
      await db.setDishIngredients(tapsi, [eggId, riceId]);
      final again = await db.getIngredientsForDishes([tapsi]);
      expect(again[tapsi]!.length, 2);

      // Delete cascades links.
      await db.deleteDish(tapsi);
      final empty = await db.getIngredientsForDishes([tapsi]);
      expect(empty[tapsi], isNull);
    });

    test('demote-only deduction rule', () async {
      final db = DatabaseHelper.instance;
      final fresh = await db.insertItem(
          Item(name: 'Demote Fresh', price: 5, usageType: UsageType.both));
      final frozen = await db.insertItem(Item(
          name: 'Demote Frozen',
          price: 5,
          usageType: UsageType.ingredientOnly,
          freshnessStatus: FreshnessStatus.frozen));
      final spoiled = await db.insertItem(Item(
          name: 'Demote Spoiled',
          price: 5,
          usageType: UsageType.ingredientOnly,
          freshnessStatus: FreshnessStatus.emptySpoiled));

      final changed =
          await db.demoteFreshIngredients([fresh, frozen, spoiled]);
      expect(changed, 1, reason: 'only the fresh ingredient may be demoted');

      final all = await db.getAllItems();
      expect(all.firstWhere((i) => i.id == fresh).freshnessStatus,
          FreshnessStatus.useSoon);
      expect(all.firstWhere((i) => i.id == frozen).freshnessStatus,
          FreshnessStatus.frozen, reason: 'never upgraded or downgraded further');
      expect(all.firstWhere((i) => i.id == spoiled).freshnessStatus,
          FreshnessStatus.emptySpoiled, reason: 'never auto-cleared');
    });
  });

  group('availability derivation', () {
    test('matrix', () {
      expect(
          deriveDishAvailability(
              [FreshnessStatus.fresh, FreshnessStatus.fresh]),
          DishAvailability.available);
      expect(
          deriveDishAvailability(
              [FreshnessStatus.fresh, FreshnessStatus.frozen]),
          DishAvailability.available,
          reason: 'frozen counts as usable');
      expect(
          deriveDishAvailability(
              [FreshnessStatus.fresh, FreshnessStatus.useSoon]),
          DishAvailability.limited);
      expect(
          deriveDishAvailability([
            FreshnessStatus.fresh,
            FreshnessStatus.emptySpoiled,
          ]),
          DishAvailability.unavailable);

      // A dish stripped of every ingredient (cascade deletes) is incomplete.
      expect(
        DishWithIngredients(dish: Dish(name: 'Empty Dish', price: 1)).availability,
        DishAvailability.unavailable,
        reason: 'empty-ingredient dishes must not show as Available',
      );
    });
  });

  group('owner consumption isolation', () {
    test('flagged transactions never reach the credit book', () async {
      final db = DatabaseHelper.instance;
      final customerId =
          await db.insertCustomer(Customer(name: 'Consumption Cust'));

      // Normal credit...
      final normalTxn = await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Normal Sale Item', 'quantity': 1, 'price': 30, 'subtotal': 30.0},
      ]);
      // ...and a personal-use one.
      if (await db.getCustomerByName('Personal Use') == null) {
        await db.insertCustomer(Customer(name: 'Personal Use'));
      }
      final personalCustomerId =
          (await db.getCustomerByName('Personal Use'))!.id!;
      await db.insertTransactionWithItems(personalCustomerId, [
        {'item_name': 'Snack Stash', 'quantity': 1, 'price': 25, 'subtotal': 25.0},
      ], isOwnerConsumption: true);

      final bookRows = await db.getActiveTransactionsWithCustomer();
      expect(bookRows.any((r) => r['id'] == normalTxn), isTrue);
      expect(bookRows.any((r) => r['customer_name'] == 'Personal Use'), isFalse,
          reason: 'owner consumption must be excluded everywhere');

      final balances = await db.getCustomersWithBalances();
      expect(balances.any((r) => r['name'] == 'Personal Use'), isFalse);

      final log = await db.getOwnerConsumptionLog();
      expect(log.length, 1);
      expect(log.first['item_names'], 'Snack Stash');
    });
  });

  group('sales intelligence', () {
    test('normalized name matching for badges', () async {
      final db = DatabaseHelper.instance;
      final customerId =
          await db.insertCustomer(Customer(name: 'Badge Cust'));
      await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Chips, Spicy', 'quantity': 2, 'price': 20, 'subtotal': 40.0},
      ]);

      final since = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
      final counts = await db.getItemSaleCountsSince(since);
      expect(counts['chips, spicy'], 1,
          reason: 'case-insensitive trim match against denormalized names');
    });

    test('spoilage totals respect date window', () async {
      final db = DatabaseHelper.instance;
      final itemId = await db.insertItem(Item(name: 'Spoil Tomatoes', price: 15));
      await db.insertSpoilage(SpoilageEntry(
        itemId: itemId,
        estimatedValue: 45.0,
        note: 'brownout',
        date: DateTime.now().toIso8601String(),
      ));
      await db.insertSpoilage(SpoilageEntry(
        itemId: itemId,
        estimatedValue: 999.0,
        date: '2020-01-01T00:00:00.000',
      ));
      final monthStart =
          DateTime(DateTime.now().year, DateTime.now().month).toIso8601String();
      final total = await db.spoilageTotalSince(monthStart);
      expect(total, greaterThanOrEqualTo(45.0));
      expect(total, lessThan(999.0),
          reason: 'entries outside the monthly window must be excluded');

      final log = await db.getSpoilageLog();
      final entry = log.firstWhere((e) => e.itemName == 'Spoil Tomatoes');
      expect(entry.note, 'brownout');
    });
  });

  group('InventoryProvider', () {
    test('badges, filters and palengke lists', () async {
      final db = DatabaseHelper.instance;
      final inv = InventoryProvider();

      final hotId = await db.insertItem(
          Item(name: 'Prov Hot Item', price: 10, createdAt: '2026-01-01T00:00:00.000'));
      final customerId =
          await db.insertCustomer(Customer(name: 'Prov Badge Cust'));
      for (int i = 0; i < 6; i++) {
        await db.insertTransactionWithItems(customerId, [
          {'item_name': 'prov hot item', 'quantity': 1, 'price': 10, 'subtotal': 10.0},
        ]);
      }

      final lowId = await db.insertItem(Item(
          name: 'Prov Low Item',
          price: 8,
          stockStatus: StockStatus.runningLow));

      await inv.loadInventory();

      expect(inv.badges[hotId]?.contains(ItemBadge.hot) ?? false, isTrue,
          reason: '6 sales this week = hot');
      expect(inv.badges.containsKey(lowId), isTrue,
          reason: 'low item with zero sales = cold badge');

      inv.setFilter(StockFilter.lowOrOut);
      expect(inv.filteredItems.any((i) => i.id == lowId), isTrue);
      expect(inv.filteredItems.any((i) => i.id == hotId), isFalse,
          reason: 'well-stocked hot item stays out of Low/Out filter');
      inv.setFilter(StockFilter.all);

      expect(inv.palengkeDryGoods.any((i) => i.id == lowId), isTrue);
    });

    test('cycle helpers persist through provider', () async {
      final db = DatabaseHelper.instance;
      final inv = InventoryProvider();
      final id = await db.insertItem(Item(name: 'Prov Cycle Me', price: 7));
      await inv.loadInventory();
      await inv.cycleStockStatus(id);
      final loaded = (await db.getAllItems()).firstWhere((i) => i.id == id);
      expect(loaded.stockStatus, StockStatus.runningLow,
          reason: 'one cycle moves well_stocked -> running_low');
    });

    test('monthly report aggregates windows', () async {
      final db = DatabaseHelper.instance;
      final inv = InventoryProvider();
      final cust = await db.insertCustomer(Customer(name: 'Report Cust'));
      await db.insertTransactionWithItems(cust, [
        {'item_name': 'Report Item A', 'quantity': 1, 'price': 100, 'subtotal': 100.0},
      ]);
      final report = await inv.monthlyReport(DateTime.now());
      expect((report['sales'] as double), greaterThanOrEqualTo(100.0));
      expect(report['top_items'], isNotEmpty);
    });
  });
}
