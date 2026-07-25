import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';

class TransactionItemLine {
  final String itemName;
  final int quantity;
  final double price;
  final double subtotal;

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
  final double totalAmount;
  final double paidAmount;
  final List<TransactionItemLine> items;

  ActiveTransaction({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.date,
    required this.totalAmount,
    required this.paidAmount,
    this.items = const [],
  });

  double get remaining => totalAmount - paidAmount;
}

class GroupedCustomer {
  final String customerName;
  final double totalAmount;
  final double paidAmount;
  final int transactionCount;
  final String oldestDate;
  final String latestDate;

  GroupedCustomer({
    required this.customerName,
    required this.totalAmount,
    required this.paidAmount,
    required this.transactionCount,
    required this.oldestDate,
    required this.latestDate,
  });

  double get remaining => totalAmount - paidAmount;
}

class TransactionsProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<ActiveTransaction> _activeTransactions = [];
  List<GroupedCustomer> _groupedCustomers = [];
  bool _isGrouped = false;

  List<ActiveTransaction> get activeTransactions => _activeTransactions;
  List<GroupedCustomer> get groupedCustomers => _groupedCustomers;
  bool get isGrouped => _isGrouped;

  void toggleGrouped() {
    _isGrouped = !_isGrouped;
    notifyListeners();
  }

  void setGrouped(bool value) {
    _isGrouped = value;
    notifyListeners();
  }

  double get totalOutstanding {
    double sum = 0;
    for (final t in _activeTransactions) sum += t.remaining;
    return sum;
  }

  double get totalOverdue {
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    double sum = 0;
    for (final t in _activeTransactions) {
      if (DateTime.parse(t.date).isBefore(cutoff)) sum += t.remaining;
    }
    return sum;
  }

  int get overdueCount {
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    int count = 0;
    for (final t in _activeTransactions) {
      if (DateTime.parse(t.date).isBefore(cutoff)) { count++; }
    }
    return count;
  }

  Future<void> loadActiveTransactions() async {
    try {
      final rows = await _db.getActiveTransactionsWithCustomer();
      _activeTransactions = rows.map((r) {
        final names = (r['item_names'] as String? ?? '').split(',');
        final qtys = (r['item_qtys'] as String? ?? '').split(',');
        final prices = (r['item_prices'] as String? ?? '').split(',');
        final subtotals = (r['item_subtotals'] as String? ?? '').split(',');

        final items = <TransactionItemLine>[];
        for (int i = 0; i < names.length; i++) {
          if (names[i].isEmpty) continue;
          items.add(TransactionItemLine(
            itemName: names[i],
            quantity: int.parse(qtys[i]),
            price: double.parse(prices[i]),
            subtotal: double.parse(subtotals[i]),
          ));
        }

        return ActiveTransaction(
          id: r['id'] as int,
          customerId: r['customer_id'] as int,
          customerName: r['customer_name'] as String,
          date: r['date'] as String,
          totalAmount: (r['total_amount'] as num).toDouble(),
          paidAmount: (r['paid_amount'] as num).toDouble(),
          items: items,
        );
      }).toList();
    } catch (_) {
      _activeTransactions = [];
    }
    notifyListeners();
  }

  Future<void> loadGroupedTransactions() async {
    try {
      final rows = await _db.getGroupedActiveTransactions();
      _groupedCustomers = rows.map((r) => GroupedCustomer(
        customerName: r['customer_name'] as String,
        totalAmount: (r['total_amount'] as num).toDouble(),
        paidAmount: (r['paid_amount'] as num).toDouble(),
        transactionCount: (r['transaction_count'] as int),
        oldestDate: r['oldest_date'] as String,
        latestDate: r['latest_date'] as String,
      )).toList();
    } catch (_) {
      _groupedCustomers = [];
    }
    notifyListeners();
  }

  Future<int> addTransactionWithItemNames(
    int customerId,
    List<String> itemNames,
    List<int> quantities,
    List<double> prices,
  ) async {
    final items = <Map<String, dynamic>>[];
    for (int i = 0; i < itemNames.length; i++) {
      final subtotal = quantities[i] * prices[i];
      items.add({
        'item_name': itemNames[i],
        'quantity': quantities[i],
        'price': prices[i],
        'subtotal': subtotal.toDouble(),
      });
    }
    final txnId = await _db.insertTransactionWithItems(customerId, items);
    await loadActiveTransactions();
    return txnId;
  }

  Future<void> processPayment(int transactionId, double amount) async {
    try {
      await _db.updateTransactionPayment(transactionId, amount);
    } catch (_) {}
    await loadActiveTransactions();
  }

  Future<void> deleteTransaction(int transactionId) async {
    await _db.deleteTransaction(transactionId);
    await loadActiveTransactions();
  }

  Future<void> reversePayment(int transactionId, double amount) async {
    await _db.reverseTransactionPayment(transactionId, amount);
    await loadActiveTransactions();
  }
}
