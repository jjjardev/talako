import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../models/customer.dart';
import '../models/dish.dart';
import '../models/item.dart';
import '../models/stock_enums.dart';
import '../utils/money.dart';
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
  List<Dish> _dishes = [];
  Map<int, Set<ItemBadge>> _badges = {};
  Map<int, int> _servedWeek = {};
  Map<int, int> _servedToday = {};
  Map<int, double> _recovered = {}; // all-time revenue per dish
  StockFilter _filter = StockFilter.all;
  bool _loading = false;

  List<Item> get items => _items;
  List<Dish> get dishes => _dishes;
  Map<int, Set<ItemBadge>> get badges => _badges;
  /// Served counts for the last 7 days, keyed by dish id.
  Map<int, int> get servedWeek => _servedWeek;

  /// Served counts for today only (cash taps + credit dish lines).
  Map<int, int> get servedToday => _servedToday;

  /// All-time revenue per dish - how much of the puhunan is earned back.
  Map<int, double> get recovered => _recovered;
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
      try {
        _recovered = await _db.getDishRevenueAllTime();
      } catch (e, s) {
        logError('load-recovered', e, s);
        _recovered = {};
      }
    } catch (e, s) {
      logError('load-inventory', e, s);
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> _loadServedCounts() async {
    try {
      final now = DateTime.now();
      final weekSince =
          now.subtract(const Duration(days: 7)).toIso8601String();
      final dayStart =
          InventoryProvider.dateStr(now); // midnight, ISO date string
      _servedWeek = await _db.getDishSaleCountsSince(weekSince);
      _servedToday = await _db.getDishSaleCountsSince(
          '${dayStart}T00:00:00.000');
    } catch (e, s) {
      logError('load-served-counts', e, s);
      _servedWeek = {};
      _servedToday = {};
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
      _dishes = await _db.getAllDishes();
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

  // ─── Dish actions ──────────────────────────────────────────────────

  Future<String?> saveDish({
    int? dishId,
    required String name,
    required double price,
    double capital = 0,
  }) async {
    try {
      if (dishId == null) {
        await _db.insertDish(Dish(name: name.trim(), price: price, capital: capital));
      } else {
        await _db.updateDish(
            Dish(id: dishId, name: name.trim(), price: price, capital: capital));
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
  final Map<int, DateTime> _lastTapAt = {};

  /// Writes a settled transaction under the hidden "Cash Sales" customer
  /// (never appears in the Credit Book), stamps dish_id + unit_capital for
  /// truthful per-dish recovery, and returns `(txnId, revenue)` for the
  /// undo snackbar.
  ///
  /// A per-dish debounce window swallows accidental double-taps so one
  /// physical press can never register two plates.
  Future<(int, double)?> recordTapSale(Dish dish, {DateTime? now}) async {
    final stamp = now ?? DateTime.now();
    final last = _lastTapAt[dish.id];
    if (last != null &&
        stamp.difference(last) < const Duration(milliseconds: 350)) {
      return null;
    }
    _lastTapAt[dish.id!] = stamp;
    try {
      var customer = await _db.getCustomerByName('Cash Sales');
      customer ??= await _db.getCustomerById(
          await _db.insertCustomer(Customer(name: 'Cash Sales')));
      final customerId = customer?.id;
      if (customerId == null || dish.id == null) return null;

      // Reheated leftovers sell first; nothing else changes on sale.
      if (await _db.getReheatLeftover(dish.id!) > 0) {
        await _db.consumeReheatLeftover(dish.id!);
      }

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
        dishId: dish.id,
      );
      logInfo('tap-sale #$txnId ${dish.name} +${dish.price} output');
      // Hot path: no full reload during a rush - bump served counts and
      // puhunan recovery.
      _servedWeek[dish.id!] = (_servedWeek[dish.id!] ?? 0) + 1;
      _servedToday[dish.id!] = (_servedToday[dish.id!] ?? 0) + 1;
      _recovered[dish.id!] = (_recovered[dish.id!] ?? 0) + dish.price;
      notifyListeners();
      return (txnId, dish.price);
    } catch (e, s) {
      logError('tap-sale', e, s);
      return null;
    }
  }

  Future<int> getReheatLeftoverPublic(int dishId) =>
      _db.getReheatLeftover(dishId);

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

  /// Owner-corrected earnings for [day] (null = use computed total).
  Future<double?> manualOutputFor(DateTime day) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('manual_output_${dateStr(day)}');
  }

  Future<void> setManualOutput(DateTime day, double? value) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'manual_output_${dateStr(day)}';
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setDouble(key, value);
    }
  }

  static DateTime _startOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  // ─── End of Day ─────────────────────────────────────────────────────

  /// Yesterday's recap waiting to be shown, if a day closed unhandled.
  Map<String, dynamic>? pendingRecap;

  static String dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Runs on Menu open: if yesterday was never closed out, computes its
  /// recap and holds it as [pendingRecap] until the UI handles it.
  /// Runs on Menu open. Builds a recap for every unclosed day and holds it
  /// in [pendingRecap] until dismissed - the closed-through marker is only
  /// advanced on dismissal, so the recap survives app restarts.
  Future<void> maybeRunEndOfDay() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = dateStr(DateTime.now());
      final lastClosed = prefs.getString('last_eod_day');
      if (lastClosed == null) {
        // First launch: baseline without a recap.
        await prefs.setString('last_eod_day', today);
        return;
      }
      if (lastClosed == today) return;
      final startDay = DateTime.tryParse(lastClosed) ?? DateTime.now();
      final endDay = DateTime.now().subtract(const Duration(days: 1));
      final rows = await _db.getDishRecapForDay(
        dateStr(startDay),
        dateStr(endDay.add(const Duration(days: 1))),
      );
      if (rows.isEmpty) {
        // Nothing to report - advance the marker quietly.
        await prefs.setString('last_eod_day', today);
        return;
      }
      pendingRecap = {
        'day': lastClosed,
        'rangeEnd': dateStr(endDay),
        'rows': rows,
      };
    } catch (e, s) {
      logError('eod-auto', e, s);
    }
  }

  /// Manual close-out: today-so-far recap + leftover prompts + marks day.
  Future<Map<String, dynamic>> recapForToday() async {
    final start = DateTime.now();
    final dayStart = DateTime(start.year, start.month, start.day);
    final rows = await _db.getDishRecapForDay(
        dayStart.toIso8601String(), start.toIso8601String());
    return {'day': dateStr(start), 'rows': rows};
  }

  Future<void> markDayClosed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_eod_day', dateStr(DateTime.now()));
    pendingRecap = null;
    notifyListeners();
  }

  /// Records leftovers chosen in the close-out sheet.
  Future<void> saveLeftovers(
      List<({int dishId, int qty, String disposition})> entries) async {
    final day = dateStr(DateTime.now());
    for (final e in entries) {
      if (e.qty <= 0) continue;
      try {
        await _db.addLeftover(e.dishId, e.qty, e.disposition, day);
        if (e.disposition == 'ingredients') {
          await _ensureLeftoverIngredient(e.dishId);
        } else if (e.disposition == 'spoiled') {
          final dish = dishByIdOf(e.dishId);
          if (dish != null) {
            await _db.insertSpoilage(SpoilageEntry(
              itemId: dish.id!,
              estimatedValue: roundMoney(dish.capital * e.qty),
              note: 'Unsold ${dish.name} (${dateStr(DateTime.now())})',
              date: DateTime.now().toIso8601String(),
            ));
          }
        }
      } catch (err, st) {
        logError('save-leftovers', err, st);
      }
    }
    await loadInventory();
  }

  Dish? dishByIdOf(int id) {
    for (final d in dishes) {
      if (d.id == id) return d;
    }
    return null;
  }

  Future<void> _ensureLeftoverIngredient(int dishId) async {
    final dish = dishByIdOf(dishId);
    if (dish == null) return;
    final name = 'Leftover: ${dish.name}';
    final item = await _db.getItemByName(name);
    if (item == null) {
      await _db.insertItem(Item(
        name: name,
        price: 0,
        usageType: UsageType.ingredientOnly,
        notes: 'Auto-created from unsold plates',
      ));
    } else {
      await _db.updateItemStockStatus(
          item.id!, StockStatus.wellStocked.dbValue);
    }
  }

  /// Undo button on the strip: deletes the most recent cash tap today
  /// (falls back to a query after app restarts).
  Future<bool> undoLastTapSale() async {
    try {
      final id = await _db.getLastTodayTapSaleId(_startOfToday().toIso8601String());
      if (id == null) return false;
      await _db.deleteTransaction(id);
      await loadInventory();
      return true;
    } catch (e, s) {
      logError('undo-last-tap', e, s);
      return false;
    }
  }

  /// Misclick protection: wipes ALL of today's cash tap-sales. Credit
  /// receipts are structurally untouched.
  Future<int> resetTodayTaps() async {
    try {
      final n = await _db.deleteTodayTapSales(_startOfToday().toIso8601String());
      await loadInventory();
      return n;
    } catch (e, s) {
      logError('reset-taps', e, s);
      return 0;
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
