import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/customer.dart';
import '../models/item.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/spoilage_entry.dart';
import '../models/stock_enums.dart';
import '../utils/app_logger.dart';

enum StockFilter { all, retail, ingredients, lowOrOut, cold }

/// Shelf ordering. Alpha works with the A-Z strip; urgent puts
/// out-of-stock first, then running low, then the rest.
enum ShelfSort { alpha, urgent }

class InventoryProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;

  List<Item> _items = [];
  StockFilter _filter = StockFilter.all;
  ShelfSort _sort = ShelfSort.alpha;
  bool _loading = false;

  List<Item> get items => _items;

  StockFilter get filter => _filter;
  ShelfSort get sort => _sort;
  bool get isLoading => _loading;

  InventoryProvider() {
    // Restore last-used Shelf layout (fire-and-forget).
    SharedPreferences.getInstance().then((p) {
      final f = p.getInt('shelf_filter');
      final so = p.getString('shelf_sort');
      var changed = false;
      if (f != null && f >= 0 && f < StockFilter.values.length && f != _filter.index) {
        _filter = StockFilter.values[f];
        changed = true;
      }
      if (so == 'urgent' && _sort != ShelfSort.urgent) {
        _sort = ShelfSort.urgent;
        changed = true;
      }
      if (changed) notifyListeners();
    }).catchError((_) {});
  }

  void setFilter(StockFilter f) {
    if (_filter == f) return;
    _filter = f;
    SharedPreferences.getInstance().then((p) => p.setInt('shelf_filter', f.index));
    notifyListeners();
  }

  void setSort(ShelfSort sort) {
    if (_sort == sort) return;
    _sort = sort;
    SharedPreferences.getInstance().then((p) => p.setString('shelf_sort', sort.name));
    notifyListeners();
  }


  bool isLowOrOut(Item i) =>
      i.stockStatus == StockStatus.runningLow ||
      i.stockStatus == StockStatus.outOfStock;

  int _statusRank(Item i) => switch (i.stockStatus) {
        StockStatus.outOfStock => 0,
        StockStatus.runningLow => 1,
        StockStatus.wellStocked => 2,
        StockStatus.cold => 3,
      };

  List<Item> get filteredItems {
    final list = switch (_filter) {
      StockFilter.all => _items,
      StockFilter.retail =>
          _items.where((i) => i.usageType != UsageType.ingredientOnly).toList(),
      StockFilter.ingredients => _items.where((i) => i.isIngredient).toList(),
      StockFilter.lowOrOut => _items.where(isLowOrOut).toList(),
      StockFilter.cold =>
          _items.where((i) => i.stockStatus == StockStatus.cold).toList(),
    };
    return _applySort(list);
  }

  /// Urgent sort: out-of-stock first, then low; name breaks ties.
  List<Item> _applySort(List<Item> list) {
    if (_sort == ShelfSort.urgent) {
      list.sort((a, b) {
        final r = _statusRank(a).compareTo(_statusRank(b));
        if (r != 0) return r;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    } else {
      list.sort((a, b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return list;
  }

  List<Item> get shoppingList {
    final lowOrOutList = _items.where(isLowOrOut).toList();
    int rank(Item i) => switch (i.stockStatus) {
          StockStatus.outOfStock => 0,
          StockStatus.runningLow => 1,
          _ => 2,
        };
    lowOrOutList.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
      return lowOrOutList;
  }

  Item? itemById(int id) {
    for (final i in _items) {
      if (i.id == id) return i;
    }
    return null;
  }

  Future<void> loadInventory() async {
    _loading = true;
    notifyListeners();
    try {
      _items = await _db.getAllItems(newestFirst: false);
    } catch (e, s) {
      logError('load-inventory', e, s);
    }
    _loading = false;
    notifyListeners();
  }





  // ─── Shelf actions ─────────────────────────────────────────────────

  final Map<int, DateTime> _lastCycle = {};

  Future<void> cycleStockStatus(int itemId) async {
    final now = DateTime.now();
    final last = _lastCycle[itemId];
    if (last != null && now.difference(last).inMilliseconds < 350) return;
    _lastCycle[itemId] = now;
    final item = itemById(itemId);
    if (item == null) return;
    try {
      await _db.updateItemStockStatus(item.id!, item.stockStatus.next().dbValue);
      await loadInventory();
    } catch (e, s) {
      logError('cycle-stock', e, s);
    }
  }


  Future<String?> addItem({
    required String name,
    required int price,
    required UsageType usageType,
    StockStatus stockStatus = StockStatus.wellStocked,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Name cannot be empty';
    try {
      if (await _db.isItemNameTaken(trimmed)) {
        return 'Item already exists';
      }
    } catch (e, s) {
      logError('check-name-taken', e, s);
    }
    try {
      await _db.insertItem(Item(
        name: trimmed,
        price: price,
        usageType: usageType,
        stockStatus: stockStatus,
      ));
      await loadInventory();
      return null;
    } catch (e) {
      if (e.toString().contains('UNIQUE') || e.toString().contains('2067')) {
        return 'Item already exists';
      }
      return 'Item already exists';
    }
  }

  /// Returns `null` on success, or an error string to show in UI.
  Future<String?> updateItem(Item item) async {
    final trimmed = item.name.trim();
    if (trimmed.isEmpty) return 'Name cannot be empty';
    try {
      if (await _db.isItemNameTaken(trimmed, excludeId: item.id)) {
        return 'Item already exists';
      }
    } catch (e, s) {
      logError('check-name-taken', e, s);
    }
    try {
      await _db.updateItem(item.copyWith(name: trimmed));
      await loadInventory();
      return null;
    } catch (e, s) {
      final msg = e.toString();
      if (msg.contains('UNIQUE') || msg.contains('2067')) {
        return 'Item already exists';
      }
      logError('update-item', e, s);
      return 'Failed to update item';
    }
  }

  /// Direct status set (Shelf long-press quick actions).
  Future<void> setStockStatus(int itemId, StockStatus status) async {
    try {
      await _db.updateItemStockStatus(itemId, status.dbValue);
      await loadInventory();
    } catch (e, s) {
      logError('set-stock-status', e, s);
    }
  }

  /// Recent-first customer list for Add Credit suggestions.
  Future<List<Customer>> recentCustomers() => _db.getCustomersByRecent();

  Future<void> restock(List<int> itemIds) async {
    try {
      await _db.markItemsRestocked(itemIds);
      await loadInventory();
    } catch (e, s) {
      logError('restock', e, s);
    }
  }




  // ─── Spoilage ──────────────────────────────────────────────────────

  Future<void> logSpoilage(int itemId, int value, String? note,
      {bool markEmpty = true}) async {
    try {
      await _db.insertSpoilage(SpoilageEntry(
        itemId: itemId,
        estimatedValue: value,
        note: note,
        date: DateTime.now().toIso8601String(),
      ));
      if (markEmpty) {
        final item = itemById(itemId);
        if (item != null) {
          await _db.updateItemStockStatus(
              itemId, StockStatus.outOfStock.dbValue);
        }
      }
      await loadInventory();
    } catch (e, s) {
      logError('log-spoilage', e, s);
    }
  }

  Future<List<SpoilageEntry>> spoilageLog({int limit = 100}) =>
      _db.getSpoilageLog(limit: limit);

  Future<int> spoilageTotalSince(DateTime since) =>
      _db.spoilageTotalSince(since.toIso8601String());

  // ─── Owner consumption ─────────────────────────────────────────────

  /// Records personal use as an owner-consumption transaction with no
  /// customer. It never appears in the Credit Book.
  Future<bool> recordOwnerUse(List<Map<String, dynamic>> lines) async {
    try {
      await _db.insertTransactionWithItems(null, lines,
          isOwnerConsumption: true);
      return true;
    } catch (e, s) {
      logError('owner-use', e, s);
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> ownerUseLog({int limit = 200}) =>
      _db.getOwnerConsumptionLog(limit: limit);

  // ─── Reports ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> monthlyReport(DateTime month) async {
    final monthStart = DateTime(month.year, month.month).toIso8601String();
    try {
      final summary = await _db.getSalesSummarySince(monthStart);
      final spoilage = await spoilageTotalSince(DateTime(month.year, month.month));
      final topItems = await _db.getTopItemsSince(monthStart);
      final ownerLog = await ownerUseLog(limit: 500);
      final ownerCountMonth = ownerLog
          .where((r) => (r['date'] as String? ?? '').compareTo(monthStart) >= 0)
          .length;
      final sales = summary['sales'] ?? 0;
      final ownerUse = summary['owner_use'] ?? 0;
      return {
        'sales': sales,
        'collected': summary['collected'] ?? 0,
        'cash_sales': summary['cash_sales'] ?? 0,
        'owner_use': ownerUse,
        'spoilage': spoilage,
        'net': sales - ownerUse - spoilage,
        'top_items': topItems,
        'owner_use_count': ownerCountMonth,
      };
    } catch (e, s) {
      logError('monthly-report', e, s);
      return {
        'sales': 0,
        'collected': 0,
        'cash_sales': 0,
        'owner_use': 0,
        'spoilage': 0,
        'net': 0,
        'top_items': const [],
        'owner_use_count': 0,
      };
    }
  }
}
