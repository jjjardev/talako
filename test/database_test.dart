import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:talako/database/database_helper.dart';
import 'package:talako/models/customer.dart';
import 'package:talako/models/item.dart';
import 'package:talako/models/spoilage_entry.dart';
import 'package:talako/providers/transactions_provider.dart';
import 'package:talako/utils/backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dbPath = await getDatabasesPath();
    await databaseFactory.deleteDatabase(join(dbPath, 'talako.db'));
  });

  group('schema v7 money', () {
    test('insert transaction stores integer minor units', () async {
      final db = DatabaseHelper.instance;
      final customerId =
          await db.insertCustomer(Customer(name: 'DB Test Customer'));

      final txnId = await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Coke 1.5L', 'quantity': 2, 'price': 4500, 'subtotal': 9000},
        {'item_name': 'Chips, spicy', 'quantity': 1, 'price': 2000, 'subtotal': 2000},
      ]);
      expect(txnId, greaterThan(0));

      final txns = await db.getActiveTransactionsWithCustomer();
      final row = txns.firstWhere((r) => r['id'] == txnId);
      expect(row['customer_name'], 'DB Test Customer');
      expect((row['total_amount'] as num).toInt(), 11000);

      final items = await db.getItemsForTransactions([txnId]);
      expect(items.length, 2);
      expect(items.any((i) => i.itemName == 'Chips, spicy'), isTrue);
      expect(items.first.subtotal, 9000);
    });

    test('partial then full payment updates status', () async {
      final db = DatabaseHelper.instance;
      final customerId =
          await db.insertCustomer(Customer(name: 'Pay Test Customer'));
      final txnId = await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Rice 1kg', 'quantity': 5, 'price': 1000, 'subtotal': 5000},
      ]);

      await db.updateTransactionPayment(txnId, 2000);
      var row = (await (await db.database)
              .query('transactions', where: 'id = ?', whereArgs: [txnId]))
          .first;
      expect((row['paid_amount'] as num).toInt(), 2000);
      expect(row['status'], 'ACTIVE');

      await db.updateTransactionPayment(txnId, 3000);
      row = (await (await db.database)
              .query('transactions', where: 'id = ?', whereArgs: [txnId]))
          .first;
      expect((row['paid_amount'] as num).toInt(), 5000);
      expect(row['status'], 'PAID');
    });

    test('overpayment is clamped to total', () async {
      final db = DatabaseHelper.instance;
      final customerId =
          await db.insertCustomer(Customer(name: 'Overpay Customer'));
      final txnId = await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Candy', 'quantity': 1, 'price': 10000, 'subtotal': 10000},
      ]);
      await db.updateTransactionPayment(txnId, 15000);
      final row = (await (await db.database)
              .query('transactions', where: 'id = ?', whereArgs: [txnId]))
          .first;
      expect((row['paid_amount'] as num).toInt(), 10000);
      expect(row['status'], 'PAID');
    });

    test('reverse payment clamps at zero and restores ACTIVE', () async {
      final db = DatabaseHelper.instance;
      final customerId =
          await db.insertCustomer(Customer(name: 'Undo Test Customer'));
      final txnId = await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Soap', 'quantity': 1, 'price': 2500, 'subtotal': 2500},
      ]);

      await db.updateTransactionPayment(txnId, 2500);
      await db.reverseTransactionPayment(txnId, 1000);
      var row = (await (await db.database)
              .query('transactions', where: 'id = ?', whereArgs: [txnId]))
          .first;
      expect((row['paid_amount'] as num).toInt(), 1500);
      expect(row['status'], 'ACTIVE');

      await db.reverseTransactionPayment(txnId, 10000);
      row = (await (await db.database)
              .query('transactions', where: 'id = ?', whereArgs: [txnId]))
          .first;
      expect((row['paid_amount'] as num).toInt(), 0);
      expect(row['status'], 'ACTIVE');
    });

    test('grouped query exposes customer_id and integer sums', () async {
      final db = DatabaseHelper.instance;
      final customerId =
          await db.insertCustomer(Customer(name: 'Grouped Customer'));
      await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Item A', 'quantity': 1, 'price': 1000, 'subtotal': 1000},
      ]);
      await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Item B', 'quantity': 2, 'price': 500, 'subtotal': 1000},
      ]);

      final rows = await db.getGroupedActiveTransactions();
      final row =
          rows.firstWhere((r) => r['customer_name'] == 'Grouped Customer');
      expect(row['customer_id'], customerId);
      expect(row['transaction_count'], 2);
      expect((row['total_amount'] as num).toInt(), 2000);
    });

    test('transaction lines resolve item_id when the name is unique', () async {
      final db = DatabaseHelper.instance;
      final itemId = await db.insertItem(Item(name: 'Resolve Me', price: 1000));
      final customerId =
          await db.insertCustomer(Customer(name: 'Resolver'));
      final txnId = await db.insertTransactionWithItems(customerId, [
        {'item_name': 'resolve me', 'quantity': 1, 'price': 1000, 'subtotal': 1000},
        {'item_name': 'Unknown item', 'quantity': 1, 'price': 500, 'subtotal': 500},
      ]);
      final lines = await db.getItemsForTransactions([txnId]);
      expect(lines.first.itemId, itemId);
      expect(lines.last.itemId, isNull);
    });

    test('case-insensitive customer lookup trims and matches', () async {
      final db = DatabaseHelper.instance;
      final id = await db.insertCustomer(Customer(name: 'Maria'));
      final found = await db.getCustomerByName('  maria ');
      expect(found?.id, id);
    });
  });

  group('integrity', () {
    test('delete cascades transaction items', () async {
      final db = DatabaseHelper.instance;
      final customerId =
          await db.insertCustomer(Customer(name: 'Delete Test Customer'));
      final txnId = await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Temp item', 'quantity': 1, 'price': 100, 'subtotal': 100},
      ]);

      await db.deleteTransaction(txnId);
      final items = await (await db.database).query('transaction_items',
          where: 'transaction_id = ?', whereArgs: [txnId]);
      final txns = await (await db.database)
          .query('transactions', where: 'id = ?', whereArgs: [txnId]);
      expect(items, isEmpty);
      expect(txns, isEmpty);
    });

    test('deleted transaction can be restored from a snapshot', () async {
      final db = DatabaseHelper.instance;
      final customerId =
          await db.insertCustomer(Customer(name: 'Snapshot Customer'));
      final txnId = await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Snapshot Item', 'quantity': 1, 'price': 700, 'subtotal': 700},
      ]);
      final snapshot = await db.snapshotTransaction(txnId);
      expect(snapshot, isNotNull);
      await db.deleteTransaction(txnId);
      expect(
          await (await db.database)
              .query('transactions', where: 'id = ?', whereArgs: [txnId]),
          isEmpty);
      await db.restoreTransactionSnapshot(snapshot!);
      final restored = await db.getItemsForTransactions([txnId]);
      expect(restored.length, 1);
      expect(restored.first.itemName, 'Snapshot Item');
    });

    test('status repair runs when the database reopens', () async {
      final db = DatabaseHelper.instance;
      final customerId =
          await db.insertCustomer(Customer(name: 'Repair Customer'));
      final txnId = await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Repair Item', 'quantity': 1, 'price': 500, 'subtotal': 500},
      ]);
      await (await db.database).update(
        'transactions',
        {'status': 'PAID'},
        where: 'id = ?',
        whereArgs: [txnId],
      );
      await db.close();
      final row = (await (await db.database)
              .query('transactions', where: 'id = ?', whereArgs: [txnId]))
          .first;
      expect(row['status'], 'ACTIVE');
    });

    test('garbage raw database fails validation and leaves live DB intact',
        () async {
      final db = DatabaseHelper.instance;
      final before = await (await db.database).query('transactions');
      final dir = await Directory.systemTemp.createTemp('talako_raw');
      final junk = File(join(dir.path, 'garbage.db'));
      await junk.writeAsString('not a sqlite database');
      await expectLater(
          db.validateRawDatabase(junk.path), throwsA(isA<Exception>()));
      final after = await (await db.database).query('transactions');
      expect(after.length, before.length);
      await dir.delete(recursive: true);
    });

    test('owner use has no customer and still renders in the log', () async {
      final db = DatabaseHelper.instance;
      final txnId = await db.insertTransactionWithItems(
        null,
        [
          {'item_name': 'Owner Snack', 'quantity': 1, 'price': 2500, 'subtotal': 2500}
        ],
        isOwnerConsumption: true,
      );
      final row = (await (await db.database)
              .query('transactions', where: 'id = ?', whereArgs: [txnId]))
          .first;
      expect(row['customer_id'], isNull);
      final log = await db.getOwnerConsumptionLog();
      final entry = log.firstWhere((r) => r['id'] == txnId);
      expect(entry['item_names'], 'Owner Snack');
    });

    test('deleting an item leaves no dangling spoilage item_id', () async {
      final db = DatabaseHelper.instance;
      final itemId = await db.insertItem(Item(name: 'Spoil Delete', price: 100));
      final spoilageId = await db.insertSpoilage(SpoilageEntry(
        itemId: itemId,
        estimatedValue: 100,
        date: DateTime.now().toIso8601String(),
      ));
      await db.deleteItem(itemId);
      final row = (await (await db.database)
              .query('spoilage_log', where: 'id = ?', whereArgs: [spoilageId]))
          .first;
      expect(row['item_id'], isNull);
    });

    test('cash sale is paid, flagged, and absent from the Credit Book',
        () async {
      final db = DatabaseHelper.instance;
      final txnId = await db.insertTransactionWithItems(
        null,
        [
          {'item_name': 'Cash Item', 'quantity': 1, 'price': 1500, 'subtotal': 1500}
        ],
        isCashSale: true,
      );
      final row = (await (await db.database)
              .query('transactions', where: 'id = ?', whereArgs: [txnId]))
          .first;
      expect((row['paid_amount'] as num).toInt(), 1500);
      expect(row['status'], 'PAID');
      expect(row['is_cash_sale'], 1);
      final book = await db.getActiveTransactionsWithCustomer();
      expect(book.any((r) => r['id'] == txnId), isFalse);
    });
  });

  group('physical book transcription', () {
    test('mark and unmark preserve debt and are idempotent', () async {
      final db = DatabaseHelper.instance;
      final customerId =
          await db.insertCustomer(Customer(name: 'Book Customer'));
      final txnId = await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Book Item', 'quantity': 1, 'price': 5000, 'subtotal': 5000},
      ]);

      await db.markTranscribed(txnId);
      var row = (await (await db.database)
              .query('transactions', where: 'id = ?', whereArgs: [txnId]))
          .first;
      expect(row['transcribed_to_book'], 1);
      expect(row['transcribed_at'], isNotNull);
      final firstStamp = row['transcribed_at'];
      await db.markTranscribed(txnId);
      row = (await (await db.database)
              .query('transactions', where: 'id = ?', whereArgs: [txnId]))
          .first;
      expect(row['transcribed_at'], firstStamp,
          reason: 'marking twice is a no-op');

      final active = await db.getActiveTransactionsWithCustomer(
          transcribedToBook: false);
      expect(active.any((r) => r['id'] == txnId), isFalse);
      final transcribed = await db.getActiveTransactionsWithCustomer(
          transcribedToBook: true);
      expect(transcribed.any((r) => r['id'] == txnId), isTrue);
      expect(await db.getCustomerOutstandingBalance(customerId), 5000);

      await db.unmarkTranscribed(txnId);
      row = (await (await db.database)
              .query('transactions', where: 'id = ?', whereArgs: [txnId]))
          .first;
      expect(row['transcribed_to_book'], 0);
      expect(row['transcribed_at'], isNull);
    });

    test('editing items clears transcription and clamps paid', () async {
      final db = DatabaseHelper.instance;
      final customerId =
          await db.insertCustomer(Customer(name: 'Edit Book Customer'));
      final txnId = await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Edit Item', 'quantity': 1, 'price': 5000, 'subtotal': 5000},
      ]);
      await db.updateTransactionPayment(txnId, 4000);
      await db.markTranscribed(txnId);

      await db.editTransactionItems(txnId, [
        {'item_name': 'Edit Item', 'quantity': 1, 'price': 3000, 'subtotal': 3000},
      ]);
      final row = (await (await db.database)
              .query('transactions', where: 'id = ?', whereArgs: [txnId]))
          .first;
      expect(row['transcribed_to_book'], 0);
      expect(row['transcribed_at'], isNull);
      expect((row['total_amount'] as num).toInt(), 3000);
      expect((row['paid_amount'] as num).toInt(), 3000);
      expect(row['status'], 'PAID');
    });

    test('provider filters active, transcribed, and all', () async {
      final db = DatabaseHelper.instance;
      final provider = TransactionsProvider();
      final customerId =
          await db.insertCustomer(Customer(name: 'Filter Customer'));
      final txnId = await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Filter Item', 'quantity': 1, 'price': 900, 'subtotal': 900},
      ]);
      await db.markTranscribed(txnId);

      await provider.loadActiveTransactions();
      expect(provider.activeTransactions.any((t) => t.id == txnId), isFalse);
      expect(provider.transcribedCount, greaterThanOrEqualTo(1));

      await provider.setFilter(CreditBookFilter.transcribed);
      expect(provider.transcribedTransactions.any((t) => t.id == txnId), isTrue);
      expect(provider.transcribedTransactions.first.transcribedToBook, isTrue);

      await provider.setFilter(CreditBookFilter.allOpen);
      expect(provider.activeTransactions.any((t) => t.id == txnId), isTrue);
    });

    test('customer sorting and LIKE escaping', () async {
      final db = DatabaseHelper.instance;
      await db.importBackup({
        'app': 'TalaKo',
        'version': 8,
        'items': [
          {'id': 901, 'name': 'Zebra', 'price': 100, 'created_at': '2026-01-01'},
          {'id': 902, 'name': 'apple', 'price': 100, 'created_at': '2026-01-01'},
          {'id': 903, 'name': '100% Juice', 'price': 100, 'created_at': '2026-01-01'},
        ],
        'customers': [
          {'id': 901, 'name': 'Zebra', 'created_at': '2026-01-01'},
          {'id': 902, 'name': 'apple', 'created_at': '2026-01-01'},
          {'id': 903, 'name': '100% Customer', 'created_at': '2026-01-01'},
        ],
        'transactions': [],
        'transaction_items': [],
        'spoilage_log': [],
      });
      final customers = await db.getAllCustomers();
      expect(customers.indexWhere((c) => c.name == 'apple'),
          lessThan(customers.indexWhere((c) => c.name == 'Zebra')));
      expect((await db.getAllCustomers(search: '%')).map((c) => c.name).toList(),
          ['100% Customer']);
      expect((await db.getAllItems(search: '%')).map((i) => i.name).toList(),
          ['100% Juice']);
      expect(await db.getAllCustomers(search: '_'), isEmpty);
      expect(await db.getAllItems(search: '_'), isEmpty);
    });
  });

  group('v2.16 credit semantics', () {
    test('global outstanding and overdue include transcribed debt', () async {
      final db = DatabaseHelper.instance;
      final customerId =
          await db.insertCustomer(Customer(name: 'Global Total Customer'));
      final txnId = await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Global Item', 'quantity': 1, 'price': 4000, 'subtotal': 4000},
      ]);
      final before = await db.getAllOutstandingTotal();
      await db.markTranscribed(txnId);
      expect(await db.getAllOutstandingTotal(), before,
          reason: 'transcription must not change global outstanding');
      expect(await db.getCustomerOutstandingBalance(customerId), 4000);

      final oldDate =
          DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
      final oldId = await (await db.database).insert('transactions', {
        'customer_id': customerId,
        'date': oldDate,
        'total_amount': 3000,
        'paid_amount': 1000,
        'status': 'ACTIVE',
        'is_owner_consumption': 0,
        'is_cash_sale': 0,
        'transcribed_to_book': 1,
        'transcribed_at': oldDate,
      });
      expect(oldId, greaterThan(0));
      expect(await db.getAllOverdueTotal(), greaterThanOrEqualTo(2000));
      expect(await db.getOverdueCountAll(), greaterThanOrEqualTo(1));
      final overdueIds = await db.getAllOverdueCustomerIds();
      expect(overdueIds.contains(customerId), isTrue);
    });

    test('transcribed view includes paid rows and count', () async {
      final db = DatabaseHelper.instance;
      final customerId =
          await db.insertCustomer(Customer(name: 'Paid Transcribed Customer'));
      final txnId = await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Paid Book Item', 'quantity': 1, 'price': 2500, 'subtotal': 2500},
      ]);
      await db.updateTransactionPayment(txnId, 2500);
      await db.markTranscribed(txnId);
      final rows = await db.getTranscribedTransactions();
      final row = rows.firstWhere((r) => r['id'] == txnId);
      expect((row['paid_amount'] as num).toInt(), 2500);
      expect((row['total_amount'] as num).toInt(), 2500);
      expect(await db.getTranscribedCount(), greaterThanOrEqualTo(1));
      expect(await db.unmarkTranscribed(txnId), 1,
          reason: 'paid transcribed rows must be untranscribable');
    });

    test('transcription guards reject owner-use and cash-sale rows', () async {
      final db = DatabaseHelper.instance;
      final ownerId = await db.insertTransactionWithItems(
        null,
        [
          {'item_name': 'Owner Guard', 'quantity': 1, 'price': 100, 'subtotal': 100}
        ],
        isOwnerConsumption: true,
      );
      final cashId = await db.insertTransactionWithItems(
        null,
        [
          {'item_name': 'Cash Guard', 'quantity': 1, 'price': 100, 'subtotal': 100}
        ],
        isCashSale: true,
      );
      expect(await db.markTranscribed(ownerId), 0);
      expect(await db.markTranscribed(cashId), 0);
      for (final id in [ownerId, cashId]) {
        final row = (await (await db.database)
                .query('transactions', where: 'id = ?', whereArgs: [id]))
            .first;
        expect(row['transcribed_to_book'], 0);
      }
    });

    test('orphan credit insert throws and zero-price rows are allowed',
        () async {
      final db = DatabaseHelper.instance;
      await expectLater(
        db.insertTransactionWithItems(
          null,
          [
            {'item_name': 'Orphan', 'quantity': 1, 'price': 100, 'subtotal': 100}
          ],
        ),
        throwsArgumentError,
      );

      final customerId =
          await db.insertCustomer(Customer(name: 'Zero Price Customer'));
      final txnId = await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Free Sample', 'quantity': 1, 'price': 0, 'subtotal': 0},
      ]);
      final row = (await (await db.database)
              .query('transactions', where: 'id = ?', whereArgs: [txnId]))
          .first;
      expect((row['total_amount'] as num).toInt(), 0);
      expect((row['paid_amount'] as num).toInt(), 0);
      expect(row['status'], 'PAID');
      final lines = await db.getItemsForTransactions([txnId]);
      expect(lines.single.itemName, 'Free Sample');
      expect(lines.single.price, 0);
    });

    test('grouped remaining includes transcribed while count is filtered',
        () async {
      final db = DatabaseHelper.instance;
      final provider = TransactionsProvider();
      final customerId =
          await db.insertCustomer(Customer(name: 'Grouped Remaining Customer'));
      await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Open Item', 'quantity': 1, 'price': 600, 'subtotal': 600},
      ]);
      final transcribedId = await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Book Item', 'quantity': 1, 'price': 400, 'subtotal': 400},
      ]);
      await db.markTranscribed(transcribedId);

      await provider.setFilter(CreditBookFilter.active);
      await provider.loadActiveTransactions();
      await provider.loadGroupedTransactions();
      final group = provider.groupedCustomers
          .firstWhere((g) => g.customerId == customerId);
      expect(group.remaining, 1000);
      expect(group.transactionCount, 1);

      final detail =
          await provider.fetchCustomerTransactions(customerId);
      expect(detail.fold<int>(0, (sum, t) => sum + t.remaining), 1000);
    });

    test('bulk settlement restores prior payment state from snapshots',
        () async {
      final db = DatabaseHelper.instance;
      final customerId =
          await db.insertCustomer(Customer(name: 'Bulk Undo Customer'));
      final a = await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Bulk A', 'quantity': 1, 'price': 1000, 'subtotal': 1000},
      ]);
      final b = await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Bulk B', 'quantity': 1, 'price': 2000, 'subtotal': 2000},
      ]);
      await db.updateTransactionPayment(a, 300);
      final result = await db.markAllCustomerReceiptsPaid(customerId);
      expect(result['settled'], 2);
      expect(result['collected'], 2700);
      await db.restorePaymentSnapshots(
          (result['snapshots'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList());
      final rowA = (await (await db.database)
              .query('transactions', where: 'id = ?', whereArgs: [a]))
          .first;
      final rowB = (await (await db.database)
              .query('transactions', where: 'id = ?', whereArgs: [b]))
          .first;
      expect((rowA['paid_amount'] as num).toInt(), 300);
      expect(rowA['status'], 'ACTIVE');
      expect((rowB['paid_amount'] as num).toInt(), 0);
      expect(rowB['status'], 'ACTIVE');
    });
  });

  group('legacy Sari v1 backup import', () {
    test('credits become minor-unit transactions; app name Sari accepted',
        () async {
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

      expect((await db.getAllItems()).any((i) => i.name == 'Siomai'), isTrue);

      final txns =
          await (await db.database).query('transactions', orderBy: 'id');
      expect(txns.length, 2);
      final paidTxn = txns
          .firstWhere((t) => (t['paid_amount'] as num).toInt() == 10000);
      expect(paidTxn['status'], 'PAID');
      expect((paidTxn['total_amount'] as num).toInt(), 10000);
      final unpaidTxn = txns
          .firstWhere((t) => (t['paid_amount'] as num).toInt() == 0);
      expect(unpaidTxn['status'], 'ACTIVE');
      expect((unpaidTxn['total_amount'] as num).toInt(), 3000);

      final lineRows =
          await (await db.database).query('transaction_items');
      expect(lineRows.length, 2);
    });
  });

  group('TransactionsProvider stitching', () {
    test('comma item names survive provider stitching', () async {
      final db = DatabaseHelper.instance;
      final provider = TransactionsProvider();
      final customerId =
          await db.insertCustomer(Customer(name: 'Comma Customer'));
      await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Chips, spicy', 'quantity': 3, 'price': 1500, 'subtotal': 4500},
        {'item_name': 'Softdrinks, 1L bottle', 'quantity': 1, 'price': 6000, 'subtotal': 6000},
      ]);

      final txns = await provider.fetchCustomerTransactions(customerId);
      expect(txns.length, 1);
      expect(txns.first.items.length, 2);
      expect(txns.first.items[0].itemName, 'Chips, spicy');
      expect(txns.first.remaining, 10500);
    });
  });

  group('backup round-trip (current format)', () {
    test('export has version, counts, checksum; restore works', () async {
      final db = DatabaseHelper.instance;
      final beforeRows = await (await db.database).query('transactions');

      final cust = await db.insertCustomer(Customer(name: 'RT Cust'));
      final txnId = await db.insertTransactionWithItems(cust, [
        {'item_name': 'RT Item', 'quantity': 2, 'price': 1500, 'subtotal': 3000},
      ]);
      await db.insertItem(Item(name: 'RT Stock Item', price: 2000));

      final exported = await db.exportBackup();
      expect(exported, isNotNull);
      expect(exported!['version'], 8);
      expect(exported['record_counts'], isA<Map>());
      expect(exported['checksum'], isA<String>());
      expect((exported['items'] as List).any((i) =>
          (i as Map)['price'] == 2000), isTrue);

      await db.importBackup({
        'app': 'TalaKo',
        'version': 8,
        'items': [],
        'customers': [],
        'transactions': [],
        'transaction_items': [],
        'spoilage_log': [],
      });
      expect(await (await db.database).query('transactions'), isEmpty);

      await db.importBackup(exported);

      final txns = await (await db.database).query('transactions');
      expect(txns.length, beforeRows.length + 1);
      expect(txns.any((t) => t['id'] == txnId), isTrue);
      expect((txns.firstWhere((t) => t['id'] == txnId)['total_amount'] as num)
          .toInt(), 3000);
      expect((await db.getAllItems()).any((i) => i.name == 'RT Stock Item'),
          isTrue);
      expect((await db.getItemsForTransactions([txnId])).first.quantity, 2);
    });

    test('v7 backup imports with transcription defaults', () async {
      final db = DatabaseHelper.instance;
      await db.importBackup({
        'app': 'TalaKo',
        'version': 7,
        'items': [],
        'customers': [
          {'id': 801, 'name': 'V7 Customer', 'created_at': '2026-01-01'},
        ],
        'transactions': [
          {
            'id': 801,
            'customer_id': 801,
            'date': '2026-01-02T00:00:00',
            'total_amount': 2500,
            'paid_amount': 0,
            'status': 'ACTIVE',
            'is_owner_consumption': 0,
            'is_cash_sale': 0,
          }
        ],
        'transaction_items': [
          {
            'id': 801,
            'transaction_id': 801,
            'item_name': 'V7 Item',
            'quantity': 1,
            'price': 2500,
            'subtotal': 2500,
          }
        ],
        'spoilage_log': [],
      });
      final row = (await (await db.database)
              .query('transactions', where: 'id = ?', whereArgs: [801]))
          .first;
      expect(row['transcribed_to_book'], 0);
      expect(row['transcribed_at'], isNull);
      expect((row['total_amount'] as num).toInt(), 2500,
          reason: 'v7 money must not be converted twice');
    });

    test('v8 export round-trips transcription state', () async {
      final db = DatabaseHelper.instance;
      final customerId =
          await db.insertCustomer(Customer(name: 'Round Trip Book'));
      final txnId = await db.insertTransactionWithItems(customerId, [
        {'item_name': 'Book RT', 'quantity': 1, 'price': 1200, 'subtotal': 1200},
      ]);
      await db.markTranscribed(txnId);
      final exported = await db.exportBackup();
      await db.importBackup(exported!);
      final row = (await (await db.database)
              .query('transactions', where: 'id = ?', whereArgs: [txnId]))
          .first;
      expect(row['transcribed_to_book'], 1);
      expect(row['transcribed_at'], isNotNull);
    });

    test('backup filenames share the timestamp pattern', () {
      final at = DateTime(2026, 10, 29, 7, 5);
      expect(BackupService.buildBackupFileName(at, 'json'),
          'talako_backup_20261029_0705.json');
      expect(BackupService.buildBackupFileName(at, '.db'),
          'talako_backup_20261029_0705.db');
    });

    test('import rejects newer schema and count mismatch before wiping',
        () async {
      final db = DatabaseHelper.instance;
      final beforeTxn = await (await db.database).query('transactions');

      await expectLater(
        db.importBackup({'app': 'TalaKo', 'version': 9}),
        throwsException,
      );
      await expectLater(
        db.importBackup({
          'app': 'TalaKo',
          'version': 7,
          'record_counts': {'items': 5},
          'items': [],
          'customers': [],
          'transactions': [],
          'transaction_items': [],
        }),
        throwsException,
      );
      final afterTxn = await (await db.database).query('transactions');
      expect(afterTxn.length, beforeTxn.length);
    });

    test('import rejects ledger-less junk before wiping', () async {
      final db = DatabaseHelper.instance;
      final beforeTxn = await (await db.database).query('transactions');
      await expectLater(
        db.importBackup({
          'app': 'TalaKo',
          'version': 7,
          'items': [],
          'customers': [],
        }),
        throwsException,
      );
      final afterTxn = await (await db.database).query('transactions');
      expect(afterTxn.length, beforeTxn.length);
    });
  });
}
