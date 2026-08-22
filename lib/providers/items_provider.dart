import 'dart:async';
import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../models/item.dart';
import '../utils/app_logger.dart';

class ItemsProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<Item> _items = [];
  String _search = '';
  bool _newestFirst = true;
  Timer? _debounce;

  List<Item> get items => _items;
  String get search => _search;
  bool get newestFirst => _newestFirst;

  Future<void> loadItems() async {
    try {
      _items = await _db.getAllItems(search: _search, newestFirst: _newestFirst);
    } catch (e, s) {
      logError('load-items', e, s);
      _items = [];
    }
    notifyListeners();
  }

  void setSearch(String query) {
    _search = query;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), loadItems);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void toggleSort() {
    _newestFirst = !_newestFirst;
    loadItems();
  }

  Future<String?> addItem(String name, double price) async {
    try {
      await _db.insertItem(Item(name: name, price: price));
      await loadItems();
      return null;
    } catch (e) {
      return 'Item already exists';
    }
  }

  Future<void> updateItem(Item item) async {
    await _db.updateItem(item);
    await loadItems();
  }

  Future<void> deleteItem(int id) async {
    await _db.deleteItem(id);
    await loadItems();
  }
}
