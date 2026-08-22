import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/stock_enums.dart';
import '../providers/inventory_provider.dart';
import 'add_edit_dish_screen.dart';

class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key});

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> with TickerProviderStateMixin {
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
            Tab(text: 'Dishes'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [_IngredientsTab(), _DishesTab()],
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

class _DishesTab extends StatelessWidget {
  const _DishesTab();

  Color _color(DishAvailability a) => switch (a) {
        DishAvailability.available => Colors.green,
        DishAvailability.limited => Colors.orange,
        DishAvailability.unavailable => Colors.red,
      };

  String _label(DishAvailability a) => switch (a) {
        DishAvailability.available => 'Available',
        DishAvailability.limited => 'Limited',
        DishAvailability.unavailable => 'Unavailable',
      };

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();

    if (inv.dishes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.restaurant_menu, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No dishes defined.\nDefine what goes into each ulam so you\nknow what you can serve.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 12),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 90),
      itemCount: inv.dishes.length,
      itemBuilder: (context, i) {
        final d = inv.dishes[i];
        final avail = d.availability;
        final color = _color(avail);
        return Dismissible(
          key: ValueKey(d.dish.id),
          direction: DismissDirection.startToEnd,
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 20),
            color: Colors.green,
            child: const Icon(Icons.check, color: Colors.white),
          ),
          confirmDismiss: (_) async {
            await context.read<InventoryProvider>().serveDish(d.dish.id!);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('"${d.dish.name}" marked as served - fresh ingredients moved to Use Soon'),
              ));
            }
            return false;
          },
          child: Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AddEditDishScreen(existing: d)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            d.dish.name.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        Text('₱${d.dish.price.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Icon(Icons.circle, size: 12, color: color),
                        const SizedBox(width: 4),
                        Text(_label(avail),
                            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        for (final ing in d.ingredients)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.circle, size: 8, color: ing.freshness.color),
                              const SizedBox(width: 3),
                              Text(ing.itemName, style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
