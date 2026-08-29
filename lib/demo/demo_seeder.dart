import '../database/database_helper.dart';
import '../models/customer.dart';
import '../models/item.dart';
import '../models/spoilage_entry.dart';
import '../models/stock_enums.dart';
import '../utils/app_logger.dart';

/// Demo preset — quantity-free, covers every Shelf + Credit Book state.
/// Local-only: inserted via `DatabaseHelper` (same path as tests).
/// Kept <120KB, <150ms seed on API 21.
class DemoSeeder {
  static const demoVersion = 1;

  static Future<bool> isAlreadySeeded() async {
    final db = DatabaseHelper.instance;
    final items = await db.getAllItems();
    return items.isNotEmpty;
  }

  static Future<void> seed() async {
    if (await isAlreadySeeded()) return;
    try {
      await _seedItems();
      await _seedCustomersAndReceipts();
      await _seedSpoilageAndOwnerUse();
    } catch (e, s) {
      logError('demo-seed', e, s);
    }
  }

  /// Force re-seed (wipes demo DB only). Used for dev reset.
  static Future<void> reseed() async {
    final db = DatabaseHelper.instance;
    // Use importBackup empty trick to wipe safely while keeping tables.
    await db.importBackup({
      'app': 'TalaKo',
      'version': 6,
      'items': [],
      'customers': [],
      'transactions': [],
      'transaction_items': [],
      'dishes': [],
      'dish_ingredients': [],
      'spoilage_log': [],
      'dish_leftovers': [],
    });
    await seed();
  }

  static Future<void> _seedItems() async {
    final db = DatabaseHelper.instance;
    final now = DateTime.now().toIso8601String();
    final items = <Item>[
      Item(name: 'Coke Mismo 200ml', price: 15, usageType: UsageType.retailOnly, stockStatus: StockStatus.wellStocked, createdAt: now),
      Item(name: 'Kopiko Brown', price: 7, usageType: UsageType.retailOnly, stockStatus: StockStatus.runningLow, createdAt: now, notes: 'Supplier: Aling Nena'),
      Item(name: 'Piatos 40g', price: 18, usageType: UsageType.retailOnly, stockStatus: StockStatus.outOfStock, createdAt: now),
      Item(name: 'Lucky Me Pancit', price: 12, usageType: UsageType.retailOnly, stockStatus: StockStatus.wellStocked, createdAt: now),
      Item(name: 'Bear Brand 33g', price: 11, usageType: UsageType.retailOnly, stockStatus: StockStatus.runningLow, createdAt: now),
      Item(name: 'Miswa', price: 8, usageType: UsageType.ingredientOnly, stockStatus: StockStatus.wellStocked, createdAt: now),
      Item(name: 'Cooking Oil 1L', price: 55, usageType: UsageType.both, stockStatus: StockStatus.outOfStock, createdAt: now),
      Item(name: 'Toyo 200ml', price: 15, usageType: UsageType.both, stockStatus: StockStatus.wellStocked, createdAt: now),
      Item(name: 'Mantika', price: 35, usageType: UsageType.ingredientOnly, stockStatus: StockStatus.wellStocked, createdAt: now),
      Item(name: 'Sardinas 555', price: 18, usageType: UsageType.retailOnly, stockStatus: StockStatus.wellStocked, createdAt: now),
      Item(name: 'Choco Mucho', price: 7, usageType: UsageType.retailOnly, stockStatus: StockStatus.cold, createdAt: now, notes: 'Discontinued 2026'),
      Item(name: 'Asin 250g', price: 10, usageType: UsageType.retailOnly, stockStatus: StockStatus.wellStocked, createdAt: now),
      Item(name: 'Itlog (egg)', price: 7, usageType: UsageType.both, stockStatus: StockStatus.runningLow, createdAt: now, notes: 'Fragile'),
      Item(name: 'Bigas 1kg', price: 50, usageType: UsageType.retailOnly, stockStatus: StockStatus.wellStocked, createdAt: now),
      Item(name: 'Load ₱50', price: 50, usageType: UsageType.retailOnly, stockStatus: StockStatus.wellStocked, createdAt: now),
      // Extra for comma regression showcase
      Item(name: 'Chips, spicy', price: 15, usageType: UsageType.retailOnly, stockStatus: StockStatus.wellStocked, createdAt: now),
    ];
    for (final it in items) {
      try {
        await db.insertItem(it);
      } catch (_) {}
    }
    // Stamp some lastStatusUpdated for shelf card "• 2d ago" showcase
    final all = await db.getAllItems();
    for (final it in all) {
      if (it.name == 'Kopiko Brown' || it.name == 'Piatos 40g') {
        // pretend scanned 2 days ago
        final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2)).toIso8601String();
        await db.updateItem(it.copyWith(lastStatusUpdated: twoDaysAgo));
      }
      if (it.name == 'Coke Mismo 200ml') {
        final today = DateTime.now().toIso8601String();
        await db.updateItem(it.copyWith(lastStatusUpdated: today, lastRestocked: today));
      }
    }
  }

  static Future<void> _seedCustomersAndReceipts() async {
    final db = DatabaseHelper.instance;

    Future<int> cust(String name) async {
      var c = await db.getCustomerByName(name);
      if (c != null) return c.id!;
      final id = await db.insertCustomer(Customer(name: name));
      return id;
    }

    final alingMyrna = await cust('Aling Myrna');
    final kuyaBoy = await cust('Kuya Boy');
    final nanayLita = await cust('Nanay Lita');
    final tatayRoger = await cust('Tatay Roger');
    final anna = await cust('Anna');
    final jose = await cust('Jose');
    final carla = await cust('Carla');
    final sara = await cust('Sara (Sari)');

    // Helper to insert receipt with custom date (bypasses insertTransactionWithItems now())
    // We insert via direct txn so we can set past dates for overdue showcase.
    Future<void> receipt(int customerId, DateTime date, List<Map<String, dynamic>> lines,
        {double paid = 0, bool owner = false, bool cash = false}) async {
      double total = 0;
      for (final l in lines) {
        total += (l['subtotal'] as num).toDouble();
      }
      final dbRaw = await db.database;
      await dbRaw.transaction((txn) async {
        final txnId = await txn.insert('transactions', {
          'customer_id': customerId,
          'date': date.toIso8601String(),
          'total_amount': total,
          'paid_amount': paid,
          'status': paid >= total ? 'PAID' : 'ACTIVE',
          'is_owner_consumption': owner ? 1 : 0,
          'is_cash_sale': cash ? 1 : 0,
          'deducted_ingredients': 0,
        });
        for (final l in lines) {
          await txn.insert('transaction_items', {
            'transaction_id': txnId,
            'item_name': l['item_name'],
            'quantity': l['quantity'],
            'price': l['price'],
            'subtotal': l['subtotal'],
            'unit_capital': 0,
          });
        }
      });
    }

    final now = DateTime.now();

    // Aling Myrna — 3 receipts (for Mark all as paid + grouped + overdue)
    await receipt(alingMyrna, now.subtract(const Duration(days: 20)), [
      {'item_name': 'Coke Mismo 200ml', 'quantity': 3, 'price': 15.0, 'subtotal': 45.0},
      {'item_name': 'Sardinas 555', 'quantity': 2, 'price': 18.0, 'subtotal': 36.0},
    ], paid: 0); // total 81, overdue red

    await receipt(alingMyrna, now.subtract(const Duration(days: 16)), [
      {'item_name': 'Kopiko Brown', 'quantity': 5, 'price': 7.0, 'subtotal': 35.0},
    ], paid: 0); // overdue red

    await receipt(alingMyrna, now.subtract(const Duration(days: 2)), [
      {'item_name': 'Chips, spicy', 'quantity': 2, 'price': 15.0, 'subtotal': 30.0},
      {'item_name': 'Piatos 40g', 'quantity': 1, 'price': 18.0, 'subtotal': 18.0},
    ], paid: 10); // partial 48 total, 10 paid

    // Kuya Boy — boundary style daily
    await receipt(kuyaBoy, now.subtract(const Duration(days: 9)), [
      {'item_name': 'Load ₱50', 'quantity': 1, 'price': 50.0, 'subtotal': 50.0},
    ], paid: 0); // orange 7+ days

    await receipt(kuyaBoy, now.subtract(const Duration(days: 1)), [
      {'item_name': 'Coke Mismo 200ml', 'quantity': 2, 'price': 15.0, 'subtotal': 30.0},
      {'item_name': 'Choco Mucho', 'quantity': 3, 'price': 7.0, 'subtotal': 21.0},
    ], paid: 0);

    // Nanay Lita — fully paid (goes to Settled Debts)
    await receipt(nanayLita, now.subtract(const Duration(days: 5)), [
      {'item_name': 'Bigas 1kg', 'quantity': 2, 'price': 50.0, 'subtotal': 100.0},
    ], paid: 100);

    await receipt(nanayLita, now.subtract(const Duration(days: 3)), [
      {'item_name': 'Cooking Oil 1L', 'quantity': 1, 'price': 55.0, 'subtotal': 55.0},
    ], paid: 55);

    // Tatay Roger — partial
    await receipt(tatayRoger, now.subtract(const Duration(days: 4)), [
      {'item_name': 'Bear Brand 33g', 'quantity': 6, 'price': 11.0, 'subtotal': 66.0},
    ], paid: 20);

    // Anna — recent single
    await receipt(anna, now.subtract(const Duration(days: 1)), [
      {'item_name': 'Lucky Me Pancit', 'quantity': 4, 'price': 12.0, 'subtotal': 48.0},
    ], paid: 0);

    // Jose — recent multi
    await receipt(jose, now, [
      {'item_name': 'Miswa', 'quantity': 3, 'price': 8.0, 'subtotal': 24.0},
      {'item_name': 'Itlog (egg)', 'quantity': 12, 'price': 7.0, 'subtotal': 84.0},
    ], paid: 0);

    // Carla — today
    await receipt(carla, now, [
      {'item_name': 'Toyo 200ml', 'quantity': 2, 'price': 15.0, 'subtotal': 30.0},
      {'item_name': 'Asin 250g', 'quantity': 1, 'price': 10.0, 'subtotal': 10.0},
    ], paid: 0);

    // Sara — small
    await receipt(sara, now.subtract(const Duration(hours: 2)), [
      {'item_name': 'Chips, spicy', 'quantity': 1, 'price': 15.0, 'subtotal': 15.0},
    ], paid: 0);

    // Additional cash sale should NOT appear in Credit Book (is_cash_sale)
    // Keep 1 cash sale hidden to prove isolation if needed — not shown in demo counts
    // await receipt(kuyaBoy, now, [ {'item_name':'Coke','quantity':1,'price':15,'subtotal':15}], paid:15, cash:true);
  }

  static Future<void> _seedSpoilageAndOwnerUse() async {
    final db = DatabaseHelper.instance;
    final items = await db.getAllItems();
    Item? find(String name) {
      for (final i in items) {
        if (i.name.toLowerCase() == name.toLowerCase()) return i;
      }
      return null;
    }

    // Spoilage: Tomatoes
    final tomatoes = find('Piatos 40g'); // reuse existing item id for spoilage demo
    if (tomatoes?.id != null) {
      await db.insertSpoilage(SpoilageEntry(
        itemId: tomatoes!.id!,
        estimatedValue: 45,
        note: 'Brownout — not cold',
        date: DateTime.now().subtract(const Duration(days: 3)).toIso8601String(),
      ));
      // second spoilage last month (outside month window)
      await db.insertSpoilage(SpoilageEntry(
        itemId: tomatoes.id!,
        estimatedValue: 999,
        note: 'Old',
        date: DateTime.now().subtract(const Duration(days: 40)).toIso8601String(),
      ));
    }

    // Owner use: snack stash under Personal Use
    var personal = await db.getCustomerByName('Personal Use');
    if (personal == null) {
      final id = await db.insertCustomer(Customer(name: 'Personal Use'));
      personal = await db.getCustomerById(id);
    }
    if (personal?.id != null) {
      final now = DateTime.now().subtract(const Duration(days: 2));
      final dbRaw = await db.database;
      await dbRaw.insert('transactions', {
        'customer_id': personal!.id!,
        'date': now.toIso8601String(),
        'total_amount': 45.0,
        'paid_amount': 45.0,
        'status': 'PAID',
        'is_owner_consumption': 1,
        'is_cash_sale': 0,
        'deducted_ingredients': 0,
      });
      final txnRow = await dbRaw.rawQuery('SELECT id FROM transactions WHERE customer_id = ? ORDER BY id DESC LIMIT 1', [personal.id!]);
      if (txnRow.isNotEmpty) {
        final tid = txnRow.first['id'] as int;
        await dbRaw.insert('transaction_items', {
          'transaction_id': tid,
          'item_name': 'Snack Stash',
          'quantity': 1,
          'price': 45.0,
          'subtotal': 45.0,
          'unit_capital': 0,
        });
      }
    }
  }
}
