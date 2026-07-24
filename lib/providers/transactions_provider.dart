import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../models/transaction_item.dart';

class TransactionsProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<Map<String, dynamic>> _activeTransactions = [];

  List<Map<String, dynamic>> get activeTransactions => _activeTransactions;

  double get totalOutstanding {
    double sum = 0;
    for (final t in _activeTransactions) {
      final total = (t['total_amount'] as num).toDouble();
      final paid = (t['paid_amount'] as num).toDouble();
      sum += total - paid;
    }
    return sum;
  }

  double get totalOverdue {
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    double sum = 0;
    for (final t in _activeTransactions) {
      final date = DateTime.parse(t['date'] as String);
      if (date.isBefore(cutoff)) {
        final total = (t['total_amount'] as num).toDouble();
        final paid = (t['paid_amount'] as num).toDouble();
        sum += total - paid;
      }
    }
    return sum;
  }

  int get overdueCount {
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    int count = 0;
    for (final t in _activeTransactions) {
      final date = DateTime.parse(t['date'] as String);
      if (date.isBefore(cutoff)) count++;
    }
    return count;
  }

  Future<void> loadActiveTransactions() async {
    try {
      _activeTransactions = await _db.getActiveTransactionsWithCustomer();
    } catch (_) {
      _activeTransactions = [];
    }
    notifyListeners();
  }

  Future<void> addTransaction(int customerId, List<Map<String, dynamic>> items) async {
    try {
      await _db.insertTransactionWithItems(customerId, items);
    } catch (_) {}
    await loadActiveTransactions();
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

  Future<List<TransactionItem>> getItems(int transactionId) async {
    return await _db.getItemsByTransaction(transactionId);
  }
}