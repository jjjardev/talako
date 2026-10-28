import 'dart:async';
import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../models/customer.dart';
import '../models/customer_summary.dart';
import '../utils/app_logger.dart';

class CustomersProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<CustomerSummary> _summaries = [];
  List<Customer> _allCustomers = [];
  String _search = '';
  Timer? _debounce;

  List<CustomerSummary> get summaries => _summaries;
  List<Customer> get customers => _allCustomers;

  Future<void> loadCustomers() async {
    try {
      final rows = await _db.getCustomersWithBalances();
      final overdueIds = await _db.getAllOverdueCustomerIds();

      final summaries = <CustomerSummary>[];
      final allCustomers = <Customer>[];

      for (final row in rows) {
        final id = row['id'] as int;
        final name = row['name'] as String;
        if (!_matchesSearch(name)) continue;
        final customer = Customer(id: id, name: name, createdAt: row['created_at'] as String);
        final balance = (row['balance'] as num).toInt();
        final overdue = overdueIds.contains(id);
        summaries.add(CustomerSummary(customer: customer, balance: balance, hasOverdue: overdue));
      }

      if (_search.isEmpty) {
        allCustomers.addAll(summaries.map((s) => s.customer));
      }

      _summaries = summaries;
      _allCustomers = allCustomers;
    } catch (e, s) {
      logError('load-customers', e, s);
      _summaries = [];
      _allCustomers = [];
    }
    notifyListeners();
  }

  Future<void> loadAllCustomers() async {
    try {
      _allCustomers = await _db.getAllCustomers(search: _search);
    } catch (e, s) {
      logError('load-all-customers', e, s);
      _allCustomers = [];
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
    _debounce = Timer(const Duration(milliseconds: 300), () {
      loadCustomers();
      loadAllCustomers();
    });
  }

  Future<Customer?> getOrCreateCustomer(String name) async {
    var customer = await _db.getCustomerByName(name);
    if (customer == null) {
      final id = await _db.insertCustomer(Customer(name: name));
      customer = await _db.getCustomerById(id);
    }
    return customer;
  }
}