import '../database/database_helper.dart';
import '../models/customer.dart';
import '../models/item.dart';
import '../models/spoilage_entry.dart';
import '../models/stock_enums.dart';
import '../utils/app_logger.dart';

/// Demo preset — quantity-free, covers every Shelf + Credit Book state.
/// All money values are integer minor units (centavos).
class DemoSeeder {
  static const demoVersion = 2;

  static int _m(num major) => (major * 100).round();

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

  static Future<void> reseed() async {
    final db = DatabaseHelper.instance;
    await db.importBackup({
      'app': 'TalaKo',
      'version': 7,
      'items': [],
      'customers': [],
      'transactions': [],
      'transaction_items': [],
      'spoilage_log': [],
    });
    await seed();
  }

  static Future<void> _seedItems() async {
    final db = DatabaseHelper.instance;
    final now = DateTime.now().toIso8601String();
    final items = <Item>[
      Item(name: 'Coke Mismo 200ml', price: _m(15), usageType: UsageType.retailOnly, stockStatus: StockStatus.wellStocked, createdAt: now),
      Item(name: 'Kopiko Brown', price: _m(7), usageType: UsageType.retailOnly, stockStatus: StockStatus.runningLow, createdAt: now, notes: 'Supplier: Aling Nena'),
      Item(name: 'Piatos 40g', price: _m(18), usageType: UsageType.retailOnly, stockStatus: StockStatus.outOfStock, createdAt: now),
      Item(name: 'Lucky Me Pancit', price: _m(12), usageType: UsageType.retailOnly, stockStatus: StockStatus.wellStocked, createdAt: now),
      Item(name: 'Bear Brand 33g', price: _m(11), usageType: UsageType.retailOnly, stockStatus: StockStatus.runningLow, createdAt: now),
      Item(name: 'Miswa', price: _m(8), usageType: UsageType.ingredientOnly, stockStatus: StockStatus.wellStocked, createdAt: now),
      Item(name: 'Cooking Oil 1L', price: _m(55), usageType: UsageType.both, stockStatus: StockStatus.outOfStock, createdAt: now),
      Item(name: 'Toyo 200ml', price: _m(15), usageType: UsageType.both, stockStatus: StockStatus.wellStocked, createdAt: now),
      Item(name: 'Mantika', price: _m(35), usageType: UsageType.ingredientOnly, stockStatus: StockStatus.wellStocked, createdAt: now),
      Item(name: 'Sardinas 555', price: _m(18), usageType: UsageType.retailOnly, stockStatus: StockStatus.wellStocked, createdAt: now),
      Item(name: 'Choco Mucho', price: _m(7), usageType: UsageType.retailOnly, stockStatus: StockStatus.cold, createdAt: now, notes: 'Discontinued 2026'),
      Item(name: 'Asin 250g', price: _m(10), usageType: UsageType.retailOnly, stockStatus: StockStatus.wellStocked, createdAt: now),
      Item(name: 'Itlog (egg)', price: _m(7), usageType: UsageType.both, stockStatus: StockStatus.runningLow, createdAt: now, notes: 'Fragile'),
      Item(name: 'Bigas 1kg', price: _m(50), usageType: UsageType.retailOnly, stockStatus: StockStatus.wellStocked, createdAt: now),
      Item(name: 'Load ₱50', price: _m(50), usageType: UsageType.retailOnly, stockStatus: StockStatus.wellStocked, createdAt: now),
      Item(name: 'Chips, spicy', price: _m(15), usageType: UsageType.retailOnly, stockStatus: StockStatus.wellStocked, createdAt: now),
    ];
    for (final it in items) {
      try {
        await db.insertItem(it);
      } catch (_) {}
    }
    final all = await db.getAllItems();
    for (final it in all) {
      if (it.name == 'Kopiko Brown' || it.name == 'Piatos 40g') {
        final twoDaysAgo =
            DateTime.now().subtract(const Duration(days: 2)).toIso8601String();
        await db.updateItem(it.copyWith(lastStatusUpdated: twoDaysAgo));
      }
      if (it.name == 'Coke Mismo 200ml') {
        final today = DateTime.now().toIso8601String();
        await db.updateItem(
            it.copyWith(lastStatusUpdated: today, lastRestocked: today));
      }
    }
  }

  static Future<void> _seedCustomersAndReceipts() async {
    final db = DatabaseHelper.instance;

    Future<int> cust(String name) async {
      var c = await db.getCustomerByName(name);
      if (c != null) return c.id!;
      return db.insertCustomer(Customer(name: name));
    }

    final alingMyrna = await cust('Aling Myrna');
    final kuyaBoy = await cust('Kuya Boy');
    final nanayLita = await cust('Nanay Lita');
    final tatayRoger = await cust('Tatay Roger');
    final anna = await cust('Anna');
    final jose = await cust('Jose');
    final carla = await cust('Carla');
    final sara = await cust('Sara (Sari)');

    Future<void> receipt(int customerId, DateTime date,
        List<Map<String, dynamic>> lines,
        {int paid = 0}) async {
      var total = 0;
      for (final l in lines) {
        total += (l['subtotal'] as num).toInt();
      }
      final dbRaw = await db.database;
      await dbRaw.transaction((txn) async {
        final txnId = await txn.insert('transactions', {
          'customer_id': customerId,
          'date': date.toIso8601String(),
          'total_amount': total,
          'paid_amount': paid,
          'status': paid >= total ? 'PAID' : 'ACTIVE',
          'is_owner_consumption': 0,
          'is_cash_sale': 0,
        });
        for (final l in lines) {
          await txn.insert('transaction_items', {
            'transaction_id': txnId,
            'item_name': l['item_name'],
            'quantity': l['quantity'],
            'price': l['price'],
            'subtotal': l['subtotal'],
          });
        }
      });
    }

    final now = DateTime.now();

    await receipt(alingMyrna, now.subtract(const Duration(days: 20)), [
      {'item_name': 'Coke Mismo 200ml', 'quantity': 3, 'price': _m(15), 'subtotal': _m(45)},
      {'item_name': 'Sardinas 555', 'quantity': 2, 'price': _m(18), 'subtotal': _m(36)},
    ]);

    await receipt(alingMyrna, now.subtract(const Duration(days: 16)), [
      {'item_name': 'Kopiko Brown', 'quantity': 5, 'price': _m(7), 'subtotal': _m(35)},
    ]);

    await receipt(alingMyrna, now.subtract(const Duration(days: 2)), [
      {'item_name': 'Chips, spicy', 'quantity': 2, 'price': _m(15), 'subtotal': _m(30)},
      {'item_name': 'Piatos 40g', 'quantity': 1, 'price': _m(18), 'subtotal': _m(18)},
    ], paid: _m(10));

    await receipt(kuyaBoy, now.subtract(const Duration(days: 9)), [
      {'item_name': 'Load ₱50', 'quantity': 1, 'price': _m(50), 'subtotal': _m(50)},
    ]);

    await receipt(kuyaBoy, now.subtract(const Duration(days: 1)), [
      {'item_name': 'Coke Mismo 200ml', 'quantity': 2, 'price': _m(15), 'subtotal': _m(30)},
      {'item_name': 'Choco Mucho', 'quantity': 3, 'price': _m(7), 'subtotal': _m(21)},
    ]);

    await receipt(nanayLita, now.subtract(const Duration(days: 5)), [
      {'item_name': 'Bigas 1kg', 'quantity': 2, 'price': _m(50), 'subtotal': _m(100)},
    ], paid: _m(100));

    await receipt(nanayLita, now.subtract(const Duration(days: 3)), [
      {'item_name': 'Cooking Oil 1L', 'quantity': 1, 'price': _m(55), 'subtotal': _m(55)},
    ], paid: _m(55));

    await receipt(tatayRoger, now.subtract(const Duration(days: 4)), [
      {'item_name': 'Bear Brand 33g', 'quantity': 6, 'price': _m(11), 'subtotal': _m(66)},
    ], paid: _m(20));

    await receipt(anna, now.subtract(const Duration(days: 1)), [
      {'item_name': 'Lucky Me Pancit', 'quantity': 4, 'price': _m(12), 'subtotal': _m(48)},
    ]);

    await receipt(jose, now, [
      {'item_name': 'Miswa', 'quantity': 3, 'price': _m(8), 'subtotal': _m(24)},
      {'item_name': 'Itlog (egg)', 'quantity': 12, 'price': _m(7), 'subtotal': _m(84)},
    ]);

    await receipt(carla, now, [
      {'item_name': 'Toyo 200ml', 'quantity': 2, 'price': _m(15), 'subtotal': _m(30)},
      {'item_name': 'Asin 250g', 'quantity': 1, 'price': _m(10), 'subtotal': _m(10)},
    ]);

    await receipt(sara, now.subtract(const Duration(hours: 2)), [
      {'item_name': 'Chips, spicy', 'quantity': 1, 'price': _m(15), 'subtotal': _m(15)},
    ]);
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

    final piatos = find('Piatos 40g');
    if (piatos?.id != null) {
      await db.insertSpoilage(SpoilageEntry(
        itemId: piatos!.id,
        estimatedValue: _m(45),
        note: 'Brownout — not cold',
        date: DateTime.now().subtract(const Duration(days: 3)).toIso8601String(),
      ));
      await db.insertSpoilage(SpoilageEntry(
        itemId: piatos.id,
        estimatedValue: _m(999),
        note: 'Old',
        date: DateTime.now().subtract(const Duration(days: 40)).toIso8601String(),
      ));
    }

    await db.insertTransactionWithItems(
      null,
      [
        {
          'item_name': 'Snack Stash',
          'quantity': 1,
          'price': _m(45),
          'subtotal': _m(45),
        }
      ],
      isOwnerConsumption: true,
    );
  }
}
