import 'dart:async';
import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../models/customer.dart';
import '../models/customer_summary.dart';
import '../models/credit_entry.dart';

class CustomersProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<CustomerSummary> _summaries = [];
  String _search = '';
  Timer? _debounce;

  List<CustomerSummary> get summaries => _summaries;
  List<Customer> get customers => _summaries.map((s) => s.customer).toList();

  Future<void> loadCustomers() async {
    try {
      final rows = await _db.getCustomersWithBalances();
      final overdueIds = await _db.getAllOverdueCustomerIds();

      final summaries = <CustomerSummary>[];

      for (final row in rows) {
        final id = row['id'] as int;
        final name = row['name'] as String;
        if (!_matchesSearch(name)) continue;
        final customer = Customer(id: id, name: name, createdAt: row['created_at'] as String);
        final balance = (row['balance'] as num).toDouble();
        final overdue = overdueIds.contains(id);
        summaries.add(CustomerSummary(customer: customer, balance: balance, hasOverdue: overdue));
      }

      _summaries = summaries;
    } catch (_) {
      _summaries = [];
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  bool _matchesSearch(String name) {
    if (_search.isEmpty) return true;
    return name.toLowerCase().contains(_search.toLowerCase());
  }

  void setSearch(String query) {
    _search = query;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), loadCustomers);
  }

  Future<Customer?> getOrCreateCustomer(String name) async {
    var customer = await _db.getCustomerByName(name);
    if (customer == null) {
      final id = await _db.insertCustomer(Customer(name: name));
      customer = await _db.getCustomerById(id);
    }
    return customer;
  }

  Future<List<CreditEntry>> getCredits(int customerId) async {
    return await _db.getCreditsByCustomer(customerId);
  }

  Future<List<CreditEntry>> getUnsettledCredits(int customerId) async {
    return await _db.getUnsettledCreditsByCustomer(customerId);
  }

  Future<List<CreditEntry>> getSettledCredits(int customerId) async {
    return await _db.getSettledCreditsByCustomer(customerId);
  }

  Future<double> getOutstandingBalance(int customerId) async {
    return await _db.getOutstandingBalance(customerId);
  }

  Future<bool> hasOverdueCredits(int customerId) async {
    return await _db.hasOverdueCredits(customerId);
  }

  Future<void> addCredit(CreditEntry credit) async {
    try {
      await _db.insertCredit(credit);
    } catch (_) {}
    await loadCustomers();
  }

  Future<void> updatePaidAmount(int creditId, double amount) async {
    try {
      await _db.updateCreditPaidAmount(creditId, amount);
    } catch (_) {}
    await loadCustomers();
  }

}
