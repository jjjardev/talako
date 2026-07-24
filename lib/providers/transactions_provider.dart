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

class TransactionsProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<ActiveTransaction> _activeTransactions = [];

  List<ActiveTransaction> get activeTransactions => _activeTransactions;

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

  Future<String?> addTransactionWithItemNames(
    int customerId,
    List<String> itemNames,
    List<int> quantities,
    List<double> prices,
  ) async {
    try {
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
      await _db.insertTransactionWithItems(customerId, items);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> processPayment(int transactionId, double amount) async {
    try {
      await _db.updateTransactionPayment(transactionId, amount);
    } catch (_) {}
    await loadActiveTransactions();
  }
}