import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../utils/app_logger.dart';

enum CreditBookFilter { allOpen, active, transcribed }

extension CreditBookFilterX on CreditBookFilter {
  String get label => switch (this) {
        CreditBookFilter.allOpen => 'All open',
        CreditBookFilter.active => 'Active',
        CreditBookFilter.transcribed => 'Transcribed',
      };
}

class TransactionItemLine {
  final String itemName;
  final int quantity;
  final int price;
  final int subtotal;

  TransactionItemLine({
    required this.itemName,
    required this.quantity,
    required this.price,
    required this.subtotal,
  });
}

class ActiveTransaction {
  final int id;
  final int customerId;
  final String customerName;
  final String date;
  final int totalAmount;
  final int paidAmount;
  final List<TransactionItemLine> items;
  final bool transcribedToBook;
  final String? transcribedAt;

  ActiveTransaction({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.date,
    required this.totalAmount,
    required this.paidAmount,
    this.items = const [],
    this.transcribedToBook = false,
    this.transcribedAt,
  });

  int get remaining => totalAmount - paidAmount;
  bool get isPaid => paidAmount >= totalAmount;
}

class GroupedCustomer {
  final int customerId;
  final String customerName;
  final int totalAmount;
  final int paidAmount;
  final int transactionCount;
  final String oldestDate;
  final String latestDate;

  GroupedCustomer({
    required this.customerId,
    required this.customerName,
    required this.totalAmount,
    required this.paidAmount,
    required this.transactionCount,
    required this.oldestDate,
    required this.latestDate,
  });

  int get remaining => totalAmount - paidAmount;
}

class BulkSettlementResult {
  final int settled;
  final int collected;
  final List<Map<String, dynamic>> snapshots;

  BulkSettlementResult({
    required this.settled,
    required this.collected,
    required this.snapshots,
  });
}

class TransactionsProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<ActiveTransaction> _activeTransactions = [];
  List<ActiveTransaction> _transcribedTransactions = [];
  List<GroupedCustomer> _groupedCustomers = [];
  bool _isGrouped = false;
  CreditBookFilter _filter = CreditBookFilter.active;
  int _transcribedCount = 0;
  int _totalOutstandingAll = 0;
  int _totalOverdueAll = 0;
  int _overdueCountAll = 0;

  TransactionsProvider() {
    SharedPreferences.getInstance().then((p) {
      final stored = p.getBool('credit_grouped');
      if (stored != null && stored != _isGrouped) {
        _isGrouped = stored;
        notifyListeners();
      }
    }).catchError((_) {});
  }

  List<ActiveTransaction> get activeTransactions => _activeTransactions;
  List<ActiveTransaction> get transcribedTransactions => _transcribedTransactions;
  List<GroupedCustomer> get groupedCustomers => _groupedCustomers;
  bool get isGrouped => _isGrouped;
  CreditBookFilter get filter => _filter;
  int get transcribedCount => _transcribedCount;
  int get totalOutstandingAll => _totalOutstandingAll;
  int get totalOverdueAll => _totalOverdueAll;
  int get overdueCountAll => _overdueCountAll;

  Future<void> setFilter(CreditBookFilter filter) async {
    if (_filter == filter) return;
    _filter = filter;
    await loadActiveTransactions();
    if (_isGrouped && filter != CreditBookFilter.transcribed) {
      await loadGroupedTransactions();
    }
  }

  void toggleGrouped() => setGrouped(!_isGrouped);

  void setGrouped(bool value) {
    if (_isGrouped == value) return;
    _isGrouped = value;
    SharedPreferences.getInstance()
        .then((p) => p.setBool('credit_grouped', value));
    notifyListeners();
  }

  int get totalOutstanding {
    var sum = 0;
    for (final t in _activeTransactions) {
      sum += t.remaining;
    }
    return sum;
  }

  int get totalOverdue {
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    var sum = 0;
    for (final t in _activeTransactions) {
      if (DateTime.parse(t.date).isBefore(cutoff)) {
        sum += t.remaining;
      }
    }
    return sum;
  }

  int get overdueCount {
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    var count = 0;
    for (final t in _activeTransactions) {
      if (DateTime.parse(t.date).isBefore(cutoff)) {
        count++;
      }
    }
    return count;
  }

  Future<List<ActiveTransaction>> _buildActiveTransactions(
    List<Map<String, dynamic>> rows,
  ) async {
    final ids = rows.map((r) => r['id'] as int).toList();
    final itemsByTxn = <int, List<TransactionItemLine>>{};
    try {
      final items = await _db.getItemsForTransactions(ids);
      for (final item in items) {
        itemsByTxn.putIfAbsent(item.transactionId, () => []).add(
              TransactionItemLine(
                itemName: item.itemName,
                quantity: item.quantity,
                price: item.price,
                subtotal: item.subtotal,
              ),
            );
      }
    } catch (e, s) {
      logError('items-for-transactions', e, s);
    }
    return rows.map((r) {
      return ActiveTransaction(
        id: r['id'] as int,
        customerId: (r['customer_id'] as int?) ?? 0,
        customerName: r['customer_name'] as String? ?? '',
        date: r['date'] as String,
        totalAmount: (r['total_amount'] as num).toInt(),
        paidAmount: (r['paid_amount'] as num).toInt(),
        items: itemsByTxn[r['id']] ?? const [],
        transcribedToBook: (r['transcribed_to_book'] as num? ?? 0) == 1,
        transcribedAt: r['transcribed_at'] as String?,
      );
    }).toList();
  }

  Future<void> loadActiveTransactions() async {
    try {
      final transcribedFlag = switch (_filter) {
        CreditBookFilter.active => false,
        CreditBookFilter.allOpen => null,
        CreditBookFilter.transcribed => true,
      };
      final rows = _filter == CreditBookFilter.transcribed
          ? await _db.getTranscribedTransactions()
          : await _db.getActiveTransactionsWithCustomer(
              transcribedToBook: transcribedFlag,
            );
      _activeTransactions = await _buildActiveTransactions(rows);
      if (_filter == CreditBookFilter.transcribed) {
        _transcribedTransactions = _activeTransactions;
      } else {
        _transcribedTransactions = await _buildActiveTransactions(
          await _db.getTranscribedTransactions(),
        );
      }
      _transcribedCount = await _db.getTranscribedCount();
      _totalOutstandingAll = await _db.getAllOutstandingTotal();
      _totalOverdueAll = await _db.getAllOverdueTotal();
      _overdueCountAll = await _db.getOverdueCountAll();
    } catch (e, s) {
      logError('load-active-transactions', e, s);
      _activeTransactions = [];
      _transcribedTransactions = [];
    }
    notifyListeners();
  }

  Future<List<ActiveTransaction>> fetchCustomerTransactions(
      int customerId) async {
    try {
      final rows =
          await _db.getActiveTransactionsWithCustomer(customerId: customerId);
      return await _buildActiveTransactions(rows);
    } catch (e, s) {
      logError('fetch-customer-transactions', e, s);
      return [];
    }
  }

  Future<void> loadGroupedTransactions() async {
    try {
      if (_filter == CreditBookFilter.transcribed) {
        _groupedCustomers = [];
      } else {
        final rows = await _db.getGroupedOpenTransactions();
        final activeCounts = <int, int>{};
        for (final t in _activeTransactions) {
          activeCounts[t.customerId] = (activeCounts[t.customerId] ?? 0) + 1;
        }
        _groupedCustomers = rows
            .where((r) {
              if (_filter == CreditBookFilter.allOpen) return true;
              return activeCounts.containsKey(r['customer_id'] as int);
            })
            .map((r) {
              final customerId = r['customer_id'] as int;
              return GroupedCustomer(
                customerId: customerId,
                customerName: r['customer_name'] as String,
                totalAmount: (r['total_amount'] as num).toInt(),
                paidAmount: (r['paid_amount'] as num).toInt(),
                transactionCount: _filter == CreditBookFilter.allOpen
                    ? (r['transaction_count'] as int)
                    : (activeCounts[customerId] ?? 0),
                oldestDate: r['oldest_date'] as String,
                latestDate: r['latest_date'] as String,
              );
            })
            .toList();
      }
    } catch (e, s) {
      logError('load-grouped-transactions', e, s);
      _groupedCustomers = [];
    }
    notifyListeners();
  }

  Future<void> _refreshAfterMutation() async {
    await loadActiveTransactions();
    if (_isGrouped) {
      await loadGroupedTransactions();
    }
  }

  Future<int> addTransactionWithItemNames(
    int? customerId,
    List<String> itemNames,
    List<int> quantities,
    List<int> prices, {
    bool isCashSale = false,
  }) async {
    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < itemNames.length; i++) {
      items.add({
        'item_name': itemNames[i],
        'quantity': quantities[i],
        'price': prices[i],
        'subtotal': quantities[i] * prices[i],
      });
    }
    final txnId = await _db.insertTransactionWithItems(
      customerId,
      items,
      isCashSale: isCashSale,
    );
    await _refreshAfterMutation();
    return txnId;
  }

  Future<void> markTranscribed(int transactionId) async {
    try {
      await _db.markTranscribed(transactionId);
    } catch (e, s) {
      logError('mark-transcribed', e, s);
    }
    await _refreshAfterMutation();
  }

  Future<void> unmarkTranscribed(int transactionId) async {
    try {
      await _db.unmarkTranscribed(transactionId);
    } catch (e, s) {
      logError('unmark-transcribed', e, s);
    }
    await _refreshAfterMutation();
  }

  Future<void> editTransactionItems(
      int transactionId, List<Map<String, dynamic>> items) async {
    try {
      await _db.editTransactionItems(transactionId, items);
    } catch (e, s) {
      logError('edit-transaction', e, s);
    }
    await _refreshAfterMutation();
  }

  Future<void> processPayment(int transactionId, int amount) async {
    try {
      await _db.updateTransactionPayment(transactionId, amount);
    } catch (e, s) {
      logError('process-payment', e, s);
    }
    await _refreshAfterMutation();
  }

  Future<Map<String, dynamic>?> deleteTransactionWithSnapshot(
      int transactionId) async {
    try {
      final snapshot = await _db.snapshotTransaction(transactionId);
      await _db.deleteTransaction(transactionId);
      await _refreshAfterMutation();
      return snapshot;
    } catch (e, s) {
      logError('delete-transaction', e, s);
      return null;
    }
  }

  Future<void> restoreTransactionSnapshot(
      Map<String, dynamic> snapshot) async {
    try {
      await _db.restoreTransactionSnapshot(snapshot);
    } catch (e, s) {
      logError('restore-transaction', e, s);
    }
    await _refreshAfterMutation();
  }

  Future<void> deleteTransaction(int transactionId) async {
    try {
      await _db.deleteTransaction(transactionId);
    } catch (e, s) {
      logError('delete-transaction', e, s);
    }
    await _refreshAfterMutation();
  }

  Future<BulkSettlementResult?> markAllPaidForCustomer(int customerId) async {
    try {
      final r = await _db.markAllCustomerReceiptsPaid(customerId);
      await _refreshAfterMutation();
      return BulkSettlementResult(
        settled: (r['settled'] as num).toInt(),
        collected: (r['collected'] as num).toInt(),
        snapshots: (r['snapshots'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );
    } catch (e, s) {
      logError('mark-all-paid', e, s);
      return null;
    }
  }

  Future<void> restorePaymentSnapshots(
      List<Map<String, dynamic>> snapshots) async {
    try {
      await _db.restorePaymentSnapshots(snapshots);
    } catch (e, s) {
      logError('restore-payment-snapshots', e, s);
    }
    await _refreshAfterMutation();
  }

  Future<void> reversePayment(int transactionId, int amount) async {
    try {
      await _db.reverseTransactionPayment(transactionId, amount);
    } catch (e, s) {
      logError('reverse-payment', e, s);
    }
    await _refreshAfterMutation();
  }
}
