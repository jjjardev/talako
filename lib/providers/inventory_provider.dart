import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../models/customer.dart';
import '../models/dish.dart';
import '../models/item.dart';
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

class InventoryProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;

  List<Item> _items = [];
  List<DishWithIngredients> _dishes = [];
  Map<int, Set<ItemBadge>> _badges = {};
  Map<int, int> _servedWeek = {};
  StockFilter _filter = StockFilter.all;
  bool _loading = false;

  List<Item> get items => _items;
  List<DishWithIngredients> get dishes => _dishes;
  Map<int, Set<ItemBadge>> get badges => _badges;
  /// Served counts for the last 7 days, keyed by dish id.
  Map<int, int> get servedWeek => _servedWeek;
  StockFilter get filter => _filter;
  bool get isLoading => _loading;

  int get bestSellerDishId {
    int bestId = -1;
    int bestCount = 0;
    _servedWeek.forEach((id, c) {
      if (c > bestCount) {
        bestCount = c;
        bestId = id;
      }
    });
    return bestCount >= 2 ? bestId : -1;
  }

  bool isLowOrOut(Item i) =>
      i.stockStatus == StockStatus.runningLow ||
      i.stockStatus == StockStatus.outOfStock;

  List<Item> get filteredItems {
    switch (_filter) {
      case StockFilter.all:
        return _items;
      case StockFilter.retail:
        return _items.where((i) => i.usageType != UsageType.ingredientOnly).toList();
      case StockFilter.ingredients:
        return _items.where((i) => i.isIngredient).toList();
      case StockFilter.lowOrOut:
        return _items.where(isLowOrOut).toList();
      case StockFilter.cold:
        return _items
            .where((i) => i.stockStatus == StockStatus.cold ||
                (_badges[i.id]?.contains(ItemBadge.cold) ?? false))
            .toList();
    }
  }

  List<Item> get palengkeDryGoods {
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

  List<Item> get palengkeWetMarket {
    final list = _items
        .where((i) =>
            i.isIngredient &&
            (i.freshnessStatus == FreshnessStatus.emptySpoiled ||
                i.freshnessStatus == FreshnessStatus.useSoon))
        .toList();
    list.sort((a, b) {
      final ra = a.freshnessStatus == FreshnessStatus.emptySpoiled ? 0 : 1;
      final rb = b.freshnessStatus == FreshnessStatus.emptySpoiled ? 0 : 1;
      final r = ra.compareTo(rb);
      if (r != 0) return r;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  void setFilter(StockFilter f) {
    _filter = f;
    notifyListeners();
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
      await _loadDishes();
      await _loadServedCounts();
    } catch (e, s) {
      logError('load-inventory', e, s);
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> _loadServedCounts() async {
    try {
      final since =
          DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
      _servedWeek = await _db.getDishSaleCountsSince(since);
    } catch (e, s) {
      logError('load-served-counts', e, s);
      _servedWeek = {};
    }
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

  Future<void> _loadDishes() async {
    try {
      final dishes = await _db.getAllDishes();
      final ingredientMap =
          await _db.getIngredientsForDishes(dishes.map((d) => d.id!).toList());
      _dishes = dishes
          .map((d) => DishWithIngredients(
                dish: d,
                ingredients: (ingredientMap[d.id] ?? const [])
                    .map(DishIngredientLine.fromItem)
                    .toList(),
              ))
          .toList();
    } catch (e, s) {
      logError('load-dishes', e, s);
      _dishes = [];
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

  Future<void> cycleFreshness(int itemId) async {
    final item = itemById(itemId);
    if (item == null) return;
    try {
      await _db.updateItemFreshness(item.id!, item.freshnessStatus.next().dbValue);
      await loadInventory();
    } catch (e, s) {
      logError('cycle-freshness', e, s);
    }
  }

  Future<String?> addItem({
    required String name,
    required double price,
    required UsageType usageType,
    bool perishable = false,
  }) async {
    try {
      await _db.insertItem(Item(
        name: name.trim(),
        price: price,
        usageType: usageType,
        perishable: perishable || usageType == UsageType.ingredientOnly,
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

  // ─── Dish actions ──────────────────────────────────────────────────

  Future<String?> saveDish({
    int? dishId,
    required String name,
    required double price,
    double capital = 0,
    required List<int> ingredientIds,
  }) async {
    if (capital > 0 && price <= capital) {
      return 'Puhunan must be below the selling price';
    }
    try {
      if (dishId == null) {
        final id =
            await _db.insertDish(Dish(name: name.trim(), price: price, capital: capital));
        await _db.setDishIngredients(id, ingredientIds);
      } else {
        await _db.updateDish(
            Dish(id: dishId, name: name.trim(), price: price, capital: capital));
        await _db.setDishIngredients(dishId, ingredientIds);
      }
      await loadInventory();
      return null;
    } catch (_) {
      return 'A dish with that name already exists';
    }
  }

  Future<void> deleteDish(int dishId) async {
    try {
      await _db.deleteDish(dishId);
      await loadInventory();
    } catch (e, s) {
      logError('delete-dish', e, s);
    }
  }

  /// Serving a dish without recording money is no longer a feature:
  /// every serve is a sale (cash tap or credit line). See recordTapSale.

  // ─── Menu sales ────────────────────────────────────────────────────

  /// One tap on a menu card = one recorded cash sale.
  ///
  /// Writes a settled transaction under the hidden "Cash Sales" customer
  /// (never appears in the Credit Book), stamps dish_id + unit_capital for
  /// truthful margins, demotes `fresh` ingredients to `use_soon`, and
  /// returns this sale's margin for the snackbar.
  Future<(int, double)?> recordTapSale(Dish dish) async {
    try {
      var customer = await _db.getCustomerByName('Cash Sales');
      customer ??= await _db.getCustomerById(
          await _db.insertCustomer(Customer(name: 'Cash Sales')));
      final customerId = customer?.id;
      if (customerId == null || dish.id == null) return null;

      final ids = await _db.getDishIngredientIds(dish.id!);
      final deducted = await _db.demoteFreshIngredients(ids) > 0;

      final txnId = await _db.insertTransactionWithItems(
        customerId,
        [
          {
            'item_name': dish.name,
            'quantity': 1,
            'price': dish.price,
            'subtotal': dish.price,
            'dish_id': dish.id,
            'unit_capital': dish.capital,
          }
        ],
        isCashSale: true,
        deductedIngredients: deducted,
        dishId: dish.id,
      );
      logInfo('tap-sale #$txnId ${dish.name} +${dish.margin}');
      await loadInventory();
      return (txnId, dish.margin);
    } catch (e, s) {
      logError('tap-sale', e, s);
      return null;
    }
  }

  /// Deletes exactly one tap-sale (Undo). Freshness stays as-is - demotion
  /// is conservative and re-tapping Fresh costs nothing.
  Future<void> deleteTapSale(int transactionId) async {
    try {
      await _db.deleteTransaction(transactionId);
      await loadInventory();
    } catch (e, s) {
      logError('delete-tap-sale', e, s);
    }
  }

  /// Combined Today numbers across cash taps AND credit dish lines.
  Future<Map<String, double>> todaySummary() =>
      _db.getMenuSummarySince(_startOfToday().toIso8601String());

  static DateTime _startOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static const int defaultDailyGoal = 500;

  Future<int> dailyGoal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('daily_profit_goal') ?? defaultDailyGoal;
  }

  Future<void> setDailyGoal(int goal) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('daily_profit_goal', goal);
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
        if (item != null && item.isIngredient) {
          await _db.updateItemFreshness(itemId, FreshnessStatus.emptySpoiled.dbValue);
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
