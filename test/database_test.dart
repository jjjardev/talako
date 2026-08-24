import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:talako/database/database_helper.dart';
import 'package:talako/models/customer.dart';
import 'package:talako/models/item.dart';
import 'package:talako/providers/transactions_provider.dart';
import 'package:talako/utils/money.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dbPath = await getDatabasesPath();
    await databaseFactory.deleteDatabase(join(dbPath, 'talako.db'));
  });

  group('DatabaseHelper', () {
    test('insert transaction with items stores exact values', () async {
      final db = DatabaseHelper.instance;
      final customerId = await db.insertCustomer(Customer(name: 'DB Test Customer'));

      final txnId = await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Coke 1.5L', 'quantity': 2, 'price': 45.0, 'subtotal': 90.0},
        {'item_name': 'Chips, spicy', 'quantity': 1, 'price': 20.0, 'subtotal': 20.0},
      ]);
      expect(txnId, greaterThan(0));

      final txns = await db.getActiveTransactionsWithCustomer();
      final row = txns.firstWhere((r) => r['id'] == txnId);
      expect(row['customer_name'], 'DB Test Customer');
      expect((row['total_amount'] as num).toDouble(), 110.0);

      final items = await db.getItemsForTransactions([txnId]);
      expect(items.length, 2);
      expect(items.any((i) => i.itemName == 'Chips, spicy'), isTrue,
          reason: 'item names containing commas must survive storage');
      expect(items.first.subtotal, 90.0);
    });

    test('partial then full payment updates status', () async {
      final db = DatabaseHelper.instance;
      final customerId = await db.insertCustomer(Customer(name: 'Pay Test Customer'));
      final txnId = await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Rice 1kg', 'quantity': 5, 'price': 10.0, 'subtotal': 50.0},
      ]);

      await db.updateTransactionPayment(txnId, 20.0);
      var row = (await (await db.database).query('transactions', where: 'id = ?', whereArgs: [txnId])).first;
      expect((row['paid_amount'] as num).toDouble(), 20.0);
      expect(row['status'], 'ACTIVE');

      await db.updateTransactionPayment(txnId, 30.0);
      row = (await (await db.database).query('transactions', where: 'id = ?', whereArgs: [txnId])).first;
      expect(moneyEquals((row['paid_amount'] as num).toDouble(), 50.0), isTrue);
      expect(row['status'], 'PAID');
    });

    test('reverse payment clamps at zero and restores ACTIVE', () async {
      final db = DatabaseHelper.instance;
      final customerId = await db.insertCustomer(Customer(name: 'Undo Test Customer'));
      final txnId = await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Soap', 'quantity': 1, 'price': 25.0, 'subtotal': 25.0},
      ]);

      await db.updateTransactionPayment(txnId, 25.0);
      await db.reverseTransactionPayment(txnId, 10.0);
      var row = (await (await db.database).query('transactions', where: 'id = ?', whereArgs: [txnId])).first;
      expect((row['paid_amount'] as num).toDouble(), 15.0);
      expect(row['status'], 'ACTIVE');

      await db.reverseTransactionPayment(txnId, 100.0);
      row = (await (await db.database).query('transactions', where: 'id = ?', whereArgs: [txnId])).first;
      expect((row['paid_amount'] as num).toDouble(), 0.0,
          reason: 'reversal must not push paid below zero');
      expect(row['status'], 'ACTIVE');
    });

    test('grouped query exposes customer_id for drill-down', () async {
      final db = DatabaseHelper.instance;
      final customerId = await db.insertCustomer(Customer(name: 'Grouped Customer'));
      await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Item A', 'quantity': 1, 'price': 10.0, 'subtotal': 10.0},
      ]);
      await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Item B', 'quantity': 2, 'price': 5.0, 'subtotal': 10.0},
      ]);

      final rows = await db.getGroupedActiveTransactions();
      final row = rows.firstWhere((r) => r['customer_name'] == 'Grouped Customer');
      expect(row['customer_id'], customerId);
      expect(row['transaction_count'], 2);
      expect((row['total_amount'] as num).toDouble(), 20.0);
    });

    test('delete cascades transaction items', () async {
      final db = DatabaseHelper.instance;
      final customerId = await db.insertCustomer(Customer(name: 'Delete Test Customer'));
      final txnId = await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Temp item', 'quantity': 1, 'price': 1.0, 'subtotal': 1.0},
      ]);

      await db.deleteTransaction(txnId);
      final items = await (await db.database).query('transaction_items', where: 'transaction_id = ?', whereArgs: [txnId]);
      final txns = await (await db.database).query('transactions', where: 'id = ?', whereArgs: [txnId]);
      expect(items, isEmpty);
      expect(txns, isEmpty);
    });
  });

  group('legacy Sari v1 backup import', () {
    test('credits become transactions; app name Sari accepted', () async {
      final db = DatabaseHelper.instance;
      final legacyBackup = {
        'app': 'Sari',
        'version': 1,
        'exported_at': '2026-07-21T02:48:56.255988',
        'items': [
          {'id': 3, 'name': 'Siomai', 'price': 5.0, 'created_at': '2026-07-20T11:44:45.968292'},
        ],
        'customers': [
          {'id': 1, 'name': 'edward', 'created_at': '2026-07-19T01:06:37.251002'},
          {'id': 2, 'name': 'Batik', 'created_at': '2026-07-19T01:56:56.854783'},
        ],
        'credits': [
          {
            'id': 1,
            'customer_id': 1,
            'item_name': 'magic',
            'quantity': 1,
            'price_per_unit': 100.0,
            'total': 100.0,
            'paid_amount': 100.0,
            'timestamp': '2026-07-19T01:06:37.350307',
          },
          {
            'id': 2,
            'customer_id': 2,
            'item_name': 'Native Coffee',
            'quantity': 2,
            'price_per_unit': 15.0,
            'total': 30.0,
            'paid_amount': 0.0,
            'timestamp': '2026-07-19T01:56:56.854783',
          },
        ],
      };

      await db.importBackup(legacyBackup);

      // Items/customers restored.
      expect((await db.getAllItems()).any((i) => i.name == 'Siomai'), isTrue);

      // Credits became transactions with correct paid/status semantics.
      final txns = await (await db.database).query('transactions', orderBy: 'id');
      expect(txns.length, 2);
      final paidTxn = txns.firstWhere((t) => (t['paid_amount'] as num).toDouble() == 100.0);
      expect(paidTxn['status'], 'PAID');
      expect(paidTxn['is_owner_consumption'], 0);
      final unpaidTxn = txns.firstWhere((t) => (t['paid_amount'] as num).toDouble() == 0.0);
      expect(unpaidTxn['status'], 'ACTIVE');

      // Lines carry the historical item names.
      final lineRows = await (await db.database)
          .query('transaction_items');
      expect(lineRows.length, 2);
    });
  });

  group('TransactionsProvider stitching', () {
    late int commaCustomerId;

    test('fetchCustomerTransactions preserves comma item names without GROUP_CONCAT parsing',
        () async {
      final db = DatabaseHelper.instance;
      final provider = TransactionsProvider();

      commaCustomerId = await db.insertCustomer(Customer(name: 'Comma Customer'));
      await db.insertTransactionWithItems(commaCustomerId, [
        {'item_name': 'Chips, spicy', 'quantity': 3, 'price': 15.0, 'subtotal': 45.0},
        {'item_name': 'Softdrinks, 1L bottle', 'quantity': 1, 'price': 60.0, 'subtotal': 60.0},
      ]);

      final txns = await provider.fetchCustomerTransactions(commaCustomerId);
      expect(txns.length, 1);
      final t = txns.first;
      expect(t.customerName, 'Comma Customer');
      expect(t.items.length, 2, reason: 'comma in item names must not split lines');
      expect(t.items[0].itemName, 'Chips, spicy');
      expect(t.items[0].quantity, 3);
      expect(t.items[1].itemName, 'Softdrinks, 1L bottle');
      expect(t.remaining, 105.0);
    });
  });  group('backup round-trip (current format)', () {
    test('export -> wipe -> import restores everything', () async {
      final db = DatabaseHelper.instance;
      final beforeRows =
          await (await db.database).query('transactions');

      // Seed distinct data.
      final cust = await db.insertCustomer(Customer(name: 'RT Cust'));
      final txnId = await db.insertTransactionWithItems(cust, [
        {'item_name': 'RT Item', 'quantity': 2, 'price': 15.0, 'subtotal': 30.0},
      ]);
      await db.insertItem(Item(name: 'RT Stock Item', price: 20));

      final exported = await db.exportBackup();
      expect(exported, isNotNull);
      expect(exported!['version'], 6);

      // Wipe via an empty TalaKo backup.
      await db.importBackup({
        'app': 'TalaKo',
        'version': 6,
        'items': [],
        'customers': [],
        'transactions': [],
        'transaction_items': [],
      });
      expect(await (await db.database).query('transactions'), isEmpty);
      expect(await (await db.database).query('dishes'), isNotNull); // tables intact

      // Restore.
      await db.importBackup(exported);

      final txns = await (await db.database).query('transactions');
      // Export captured every prior row too - delta must be exactly our seed.
      expect(txns.length, beforeRows.length + 1,
          reason: 'wipe removed history, restore brought export contents back');
      expect(txns.any((t) => t['id'] == txnId), isTrue);
      final seeded = txns.firstWhere((t) => t['id'] == txnId);
      expect(seeded['status'], 'ACTIVE');

      final items = await db.getAllItems();
      expect(items.any((i) => i.name == 'RT Stock Item'), isTrue);
      expect((await db.getAllCustomers()).any((c) => c.name == 'RT Cust'),
          isTrue);

      // Lines restored with quantities.
      final lines = await db.getItemsForTransactions([txnId]);
      expect(lines.length, 1);
      expect(lines.first.quantity, 2);
    });

    test('import rejects ledger-less junk before wiping', () async {
      final db = DatabaseHelper.instance;
      final beforeTxn =
          await (await db.database).query('transactions');

      await expectLater(
        db.importBackup({
          'app': 'TalaKo',
          'version': 6,
          'items': [],
          'customers': [],
        }),
        throwsException,
      );

      final afterTxn = await (await db.database).query('transactions');
      expect(afterTxn.length, beforeTxn.length,
          reason: 'validation must run BEFORE the destructive wipe');
    });
  });
}
