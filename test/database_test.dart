import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:talako/database/database_helper.dart';
import 'package:talako/models/customer.dart';
import 'package:talako/providers/transactions_provider.dart';
import 'package:talako/utils/money.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
  });
}
