import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/customer.dart';
import '../models/item.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/spoilage_entry.dart';
import '../models/stock_enums.dart';
import '../utils/app_logger.dart';

enum ItemBadge { hot, cooling, cold, fresh }

extension ItemBadgeX on ItemBadge {
  String get label => switch (this) {
        ItemBadge.hot => 'Hot',
        ItemBadge.cooling => 'Cooling',
        ItemBadge.cold => 'Cold',
        ItemBadge.fresh => 'New',
      };

  IconData get icon => switch (this) {
        ItemBadge.hot => Icons.local_fire_department,
        ItemBadge.cooling => Icons.device_thermostat,
        ItemBadge.cold => Icons.ac_unit,
        ItemBadge.fresh => Icons.fiber_new,
      };

  Color get color => switch (this) {
        ItemBadge.hot => Colors.red,
        ItemBadge.cooling => Colors.orange,
        ItemBadge.cold => Colors.lightBlue,
        ItemBadge.fresh => Colors.green,
      };
}

enum StockFilter { all, retail, ingredients, lowOrOut, cold }

/// Shelf ordering. Alpha works with the A-Z strip; urgent puts
/// out-of-stock first, then running low, then the rest.
enum ShelfSort { alpha, urgent }

class InventoryProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;

  List<Item> _items = [];
  Map<int, Set<ItemBadge>> _badges = {};
  StockFilter _filter = StockFilter.all;
  ShelfSort _sort = ShelfSort.alpha;
  bool _loading = false;

  List<Item> get items => _items;
  Map<int, Set<ItemBadge>> get badges => _badges;

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
      StockFilter.cold => _items
          .where((i) => i.stockStatus == StockStatus.cold ||
              (_badges[i.id]?.contains(ItemBadge.cold) ?? false))
          .toList(),
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
      await _loadBadges();
    } catch (e, s) {
      logError('load-inventory', e, s);
    }
    _loading = false;
    notifyListeners();
  }


  String _normalize(String name) => name.trim().toLowerCase();

  Future<void> _loadBadges() async {
    try {
      final now = DateTime.now();
      final since7 = now.subtract(const Duration(days: 7)).toIso8601String();
      final since14 = now.subtract(const Duration(days: 14)).toIso8601String();
      final newCutoff = now.subtract(const Duration(days: 7)).toIso8601String();

      final counts7 = await _db.getItemSaleCountsSince(since7);
      final counts14 = await _db.getItemSaleCountsSince(since14);

      final result = <int, Set<ItemBadge>>{};
      for (final item in _items) {
        if (item.id == null) continue;
        final badges = <ItemBadge>{};
        final c7 = counts7[_normalize(item.name)] ?? 0;
        final c14 = counts14[_normalize(item.name)] ?? 0;
        final prevWeek = c14 - c7;

        if (DateTime.tryParse(item.createdAt)
                ?.isAfter(DateTime.parse(newCutoff)) ??
            false) {
          badges.add(ItemBadge.fresh);
        } else {
          if (c7 >= 5) badges.add(ItemBadge.hot);
          if (prevWeek >= 5 && c7 > 0 && c7 < 5) badges.add(ItemBadge.cooling);
          // Existed before the observation window yet zero sales = cold.
          if (c14 == 0 && item.createdAt.compareTo(since14) < 0) {
            badges.add(ItemBadge.cold);
          }
        }
        if (item.stockStatus == StockStatus.cold) badges.add(ItemBadge.cold);
        if (badges.isNotEmpty) result[item.id!] = badges;
      }
      _badges = result;
    } catch (e, s) {
      logError('load-badges', e, s);
      _badges = {};
    }
  }


  // ─── Shelf actions ─────────────────────────────────────────────────

  Future<void> cycleStockStatus(int itemId) async {
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
    required double price,
    required UsageType usageType,
  }) async {
    try {
      await _db.insertItem(Item(
        name: name.trim(),
        price: price,
        usageType: usageType,
      ));
      await loadInventory();
      return null;
    } catch (_) {
      return 'Item already exists';
    }
  }

  Future<void> updateItem(Item item) async {
    try {
      await _db.updateItem(item);
      await loadInventory();
    } catch (e, s) {
      logError('update-item', e, s);
    }
  }

  Future<void> deleteItem(int itemId) async {
    try {
      await _db.deleteItem(itemId);
      await loadInventory();
    } catch (e, s) {
      logError('delete-item', e, s);
    }
  }

  Future<void> restock(List<int> itemIds) async {
    try {
      await _db.markItemsRestocked(itemIds);
      await loadInventory();
    } catch (e, s) {
      logError('restock', e, s);
    }
  }




  // ─── Spoilage ──────────────────────────────────────────────────────

  Future<void> logSpoilage(int itemId, double value, String? note,
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

  Future<double> spoilageTotalSince(DateTime since) =>
      _db.spoilageTotalSince(since.toIso8601String());

  // ─── Owner consumption ─────────────────────────────────────────────

  /// Records personal use as a flagged transaction under the hidden
  /// "Personal Use" pseudo-customer so it never appears in the Credit Book.
  Future<bool> recordOwnerUse(List<Map<String, dynamic>> lines) async {
    try {
      var customer = await _db.getCustomerByName('Personal Use');
      customer ??= await _db.getCustomerById(
          await _db.insertCustomer(Customer(name: 'Personal Use')));
      final customerId = customer?.id;
      if (customerId == null) return false;
      await _db.insertTransactionWithItems(customerId, lines,
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
      return {
        'sales': summary['sales'] ?? 0.0,
        'collected': summary['collected'] ?? 0.0,
        'owner_use': summary['owner_use'] ?? 0.0,
        'spoilage': spoilage,
        'top_items': topItems,
        'owner_use_count': ownerCountMonth,
      };
    } catch (e, s) {
      logError('monthly-report', e, s);
      return {
        'sales': 0.0,
        'collected': 0.0,
        'owner_use': 0.0,
        'spoilage': 0.0,
        'top_items': const [],
        'owner_use_count': 0,
      };
    }
  }
}
