import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/dish.dart';
import '../models/stock_enums.dart';
import '../providers/inventory_provider.dart';
import '../utils/currency_format.dart';
import '../utils/snackbars.dart';
import 'add_edit_dish_screen.dart';

class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key});

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen>
    with TickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InventoryProvider>().loadInventory();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Ingredients'),
            Tab(text: 'Menu'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [_IngredientsTab(), _MenuTab()],
          ),
        ),
      ],
    );
  }
}

class _IngredientsTab extends StatelessWidget {
  const _IngredientsTab();

  String _relative(String? iso) {
    final dt = DateTime.tryParse(iso ?? '');
    if (dt == null) return '';
    final d = DateTime.now().difference(dt);
    return d.inDays <= 0 ? 'today' : '${d.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    final ingredients = inv.items.where((i) => i.isIngredient).toList();

    if (ingredients.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.soup_kitchen_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No ingredients yet.\nAdd items and mark them as Ingredient or Both.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 90),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.05,
      ),
      itemCount: ingredients.length,
      itemBuilder: (context, i) {
        final item = ingredients[i];
        final dishCount = inv.dishes
            .where((d) => d.ingredients.any((line) => line.itemId == item.id))
            .length;
        final color = item.freshnessStatus.color;
        return Card(
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: () => context.read<InventoryProvider>().cycleFreshness(item.id!),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(height: 5, color: color),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Row(
                        children: [
                          Icon(Icons.circle, size: 10, color: color),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(item.freshnessStatus.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (item.lastRestocked != null) 'bought ${_relative(item.lastRestocked)}',
                          if (dishCount > 0) 'in $dishCount dishes',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MenuTab extends StatefulWidget {
  const _MenuTab();

  @override
  State<_MenuTab> createState() => _MenuTabState();
}

class _MenuTabState extends State<_MenuTab> {
  Map<String, double>? _today;
  int _goal = InventoryProvider.defaultDailyGoal;

  @override
  void initState() {
    super.initState();
    _refreshToday();
  }

  Future<void> _refreshToday() async {
    final inv = context.read<InventoryProvider>();
    final summary = await inv.todaySummary();
    final goal = await inv.dailyGoal();
    if (!mounted) return;
    setState(() {
      _today = summary;
      _goal = goal;
    });
  }

  Future<void> _sell(DishWithIngredients d) async {
    HapticFeedback.mediumImpact();
    final inv = context.read<InventoryProvider>();
    final result = await inv.recordTapSale(d.dish);
    if (!mounted || result == null) return;
    final (txnId, margin) = result;
    await _refreshToday();
    if (!mounted) return;
    showAutoDismissSnackBar(
      ScaffoldMessenger.of(context),
      message:
          '+${formatCurrency(margin)} profit · Today ${formatCurrency(_today?['profit'] ?? margin)}',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          await context.read<InventoryProvider>().deleteTapSale(txnId);
          _refreshToday();
        },
      ),
    );
  }

  Future<void> _openEditor({DishWithIngredients? existing}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddEditDishScreen(existing: existing)),
    );
    if (mounted) {
      await context.read<InventoryProvider>().loadInventory();
      _refreshToday();
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    final dishes = inv.dishes;

    return Column(
      children: [
        _TodayStrip(today: _today, goal: _goal),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(
            children: [
              Text('${dishes.length} dishes',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Dish'),
              ),
            ],
          ),
        ),
        Expanded(
          child: dishes.isEmpty
              ? _EmptyMenu(onAdd: () => _openEditor())
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 90),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.88,
                  ),
                  itemCount: dishes.length,
                  itemBuilder: (context, i) {
                    final d = dishes[i];
                    return _MenuCard(
                      data: d,
                      servedWeek: inv.servedWeek[d.dish.id] ?? 0,
                      isBestSeller: inv.bestSellerDishId == d.dish.id,
                      onTap: () => _sell(d),
                      onLongPress: () => _openEditor(existing: d),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _TodayStrip extends StatelessWidget {
  final Map<String, double>? today;
  final int goal;

  const _TodayStrip({required this.today, required this.goal});

  @override
  Widget build(BuildContext context) {
    final sales = today?['sales'] ?? 0;
    final profit = today?['profit'] ?? 0;
    final plates = (today?['plates'] ?? 0).toInt();
    final passed = profit >= goal && goal > 0;
    final progress = goal > 0 ? (profit / goal).clamp(0.0, 1.0) : 0.0;
    final accent = passed ? Colors.green : Colors.teal;

    return Card(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      color: passed ? Colors.green.shade50 : Colors.teal.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Today',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                const Spacer(),
                if (passed) ...[
                  const Icon(Icons.check_circle, size: 16, color: Colors.green),
                  const SizedBox(width: 4),
                  const Text('Goal passed!',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.green)),
                  const SizedBox(width: 8),
                ],
                Text('$plates plates',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatCurrency(profit),
                    style: TextStyle(
                        fontSize: 26, fontWeight: FontWeight.bold, color: accent)),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('profit · ${formatCurrency(sales)} sales',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                ),
                const Spacer(),
                Text('of ${formatCurrency(goal.toDouble())}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.grey.shade300,
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final DishWithIngredients data;
  final int servedWeek;
  final bool isBestSeller;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _MenuCard({
    required this.data,
    required this.servedWeek,
    required this.isBestSeller,
    required this.onTap,
    required this.onLongPress,
  });

  Color get _availabilityColor => switch (data.availability) {
        DishAvailability.available => Colors.green,
        DishAvailability.limited => Colors.orange,
        DishAvailability.unavailable => Colors.red,
      };

  @override
  Widget build(BuildContext context) {
    final dish = data.dish;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 5, color: _availabilityColor),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(dish.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
                      if (isBestSeller)
                        const Text('🏆', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(formatCurrency(dish.price),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Row(
                    children: [
                      Icon(Icons.circle, size: 9, color: _availabilityColor),
                      const SizedBox(width: 4),
                      Text('+${formatCurrency(dish.margin)}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: dish.thinMargin ? Colors.orange : Colors.green)),
                      const SizedBox(width: 4),
                      if (dish.capital > 0)
                        Text('${(dish.marginRate * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                                fontSize: 11,
                                color: dish.thinMargin ? Colors.orange : Colors.grey.shade600)),
                      if (dish.thinMargin) ...[
                        const SizedBox(width: 4),
                        const Text('⚠️', style: TextStyle(fontSize: 11)),
                      ],
                    ],
                  ),
                  if (servedWeek > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('served ${servedWeek}x this week',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyMenu extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyMenu({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.restaurant_menu, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No menu items yet.\nAdd your ulam with its puhunan and price,\nthen tap to record every sale.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('New Dish'),
          ),
        ],
      ),
    );
  }
}
