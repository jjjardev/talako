import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/dish.dart';
import '../models/stock_enums.dart';
import '../providers/inventory_provider.dart';
import '../utils/currency_format.dart';
import '../utils/snackbars.dart';
import 'add_edit_dish_screen.dart';
import 'close_out_sheet.dart';
import '../widgets/alphabet_strip.dart';
import 'package:share_plus/share_plus.dart';

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

class _IngredientsTab extends StatefulWidget {
  const _IngredientsTab();

  @override
  State<_IngredientsTab> createState() => _IngredientsTabState();
}

class _IngredientsTabState extends State<_IngredientsTab> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }


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

    final sorted = [...ingredients]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return LayoutBuilder(
      builder: (context, cons) {
      final offsets =
          AlphabetStrip.letterOffsets(sorted.map((i) => i.name).toList());
      const extent = 145.0;
      return Stack(
        children: [
          GridView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(10, 8, 30, 90),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: extent,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.05,
            ),
            itemCount: sorted.length,
        itemBuilder: (context, i) {
          final item = sorted[i];
        final bandColor = item.stockStatus.color;
        return Card(
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: () => context.read<InventoryProvider>().cycleStockStatus(item.id!),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(height: 5, color: bandColor),
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
                          Icon(Icons.circle, size: 10, color: item.stockStatus.color),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(item.stockStatus.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600, color: item.stockStatus.color)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (item.lastRestocked != null)
                            'bought ${_relative(item.lastRestocked)}',
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
      ),
      Positioned(
        right: 2,
        top: 0,
        bottom: 90,
        child: Center(
          child: AlphabetStrip(
            letters: offsets.keys.toList(),
            onLetter: (l) {
              final target = AlphabetStrip.gridScrollOffsetFor(
                itemIndex: offsets[l]!,
                availableWidth: cons.maxWidth,
                horizontalPadding: 40,
                maxCrossAxisExtent: 145,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.05,
                leadingVerticalInset: 8,
              );
              _scroll.animateTo(
                target.clamp(0.0, _scroll.position.maxScrollExtent),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
              );
            },
          ),
        ),
      ),
    ],
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final inv = context.read<InventoryProvider>();
      await inv.maybeRunEndOfDay();
      await _refreshToday();
      if (mounted) setState(() {});
    });
  }

  Future<void> _refreshToday() async {
    final summary = await context.read<InventoryProvider>().todaySummary();
    if (!mounted) return;
    setState(() => _today = summary);
  }

  Future<void> _undoLast() async {
    final ok = await context.read<InventoryProvider>().undoLastTapSale();
    if (!mounted) return;
    await _refreshToday();
    if (!mounted) return;
    showAutoDismissSnackBar(
      ScaffoldMessenger.of(context),
      message: ok ? 'Last sale undone' : 'No tap-sales to undo today',
    );
  }

  Future<void> _resetTaps() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset today\'s taps?'),
        content: const Text(
            'This deletes every cash sale you tapped today (misclick cleanup). '
            'Customer credit receipts are NOT touched.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final n = await context.read<InventoryProvider>().resetTodayTaps();
    if (!mounted) return;
    await _refreshToday();
    if (!mounted) return;
    showAutoDismissSnackBar(
      ScaffoldMessenger.of(context),
      message: '$n tapped sale${n == 1 ? '' : 's'} removed',
    );
  }

  Future<void> _openEditor({Dish? existing}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddEditDishScreen(existing: existing)),
    );
    if (mounted) {
      await context.read<InventoryProvider>().loadInventory();
      _refreshToday();
    }
  }

  Future<void> _openCloseOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End this day?'),
        content: const Text(
            'This shows your sales recap and asks about leftover cooked '
            'plates. You can still use the app afterwards.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, end day'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const CloseOutSheet(),
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
        if (inv.pendingRecap != null)
          RecapCard(
            recap: inv.pendingRecap!,
            onDismiss: () async {
              await inv.markDayClosed();
              if (mounted) setState(() {});
            },
          ),
        _TodayStrip(
          today: _today,
          canUndo: (_today?['plates'] ?? 0) > 0,
          onUndo: _undoLast,
          onReset: _resetTaps,
          onEndDay: dishes.isEmpty ? null : _openCloseOut,
        ),
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
                      dish: dishes[i],
                      servedToday: inv.servedToday[dishes[i].id] ?? 0,
                      servedWeek: inv.servedWeek[dishes[i].id] ?? 0,
                      isBestSeller: inv.bestSellerDishId == dishes[i].id,
                      onTap: () => _sell(dishes[i]),
                      onLongPress: () => _openEditor(existing: d),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _sell(Dish d) async {
    HapticFeedback.mediumImpact();
    final inv = context.read<InventoryProvider>();
    final result = await inv.recordTapSale(d);
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
}

class _TodayStrip extends StatelessWidget {
  final Map<String, double>? today;
  final bool canUndo;
  final VoidCallback onUndo;
  final VoidCallback onReset;
  final VoidCallback? onEndDay;

  const _TodayStrip({
    required this.today,
    required this.canUndo,
    required this.onUndo,
    required this.onReset,
    this.onEndDay,
  });

  @override
  Widget build(BuildContext context) {
    final sales = today?['sales'] ?? 0;
    final profit = today?['profit'] ?? 0;
    final plates = (today?['plates'] ?? 0).toInt();

    return Card(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      color: Colors.teal.shade50,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Today',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade800)),
                const SizedBox(width: 8),
                Text(formatCurrency(profit),
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade900)),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('$plates plates · ${formatCurrency(sales)}',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade800)),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Undo last tap-sale',
                  style: IconButton.styleFrom(foregroundColor: Colors.teal.shade800),
                  icon: const Icon(Icons.undo, size: 20),
                  onPressed: canUndo ? onUndo : null,
                ),
                IconButton(
                  tooltip: 'Reset all taps today',
                  style: IconButton.styleFrom(foregroundColor: Colors.red.shade700),
                  icon: const Icon(Icons.restart_alt, size: 20),
                  onPressed: onReset,
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onEndDay,
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.teal.shade800),
                  icon: const Icon(Icons.nightlight_outlined, size: 16),
                  label: const Text('End Day'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class RecapCard extends StatelessWidget {
  final Map<String, dynamic> recap;
  final VoidCallback onDismiss;

  const RecapCard({super.key, required this.recap, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final rows = (recap['rows'] as List).cast<Map<String, dynamic>>();
    double sales = 0, profit = 0;
    int plates = 0;
    for (final r in rows) {
      sales += (r['sales'] as num).toDouble();
      profit += (r['profit'] as num).toDouble();
      plates += (r['plates'] as int);
    }
    final day = recap['day'] as String? ?? '';
    final rangeEnd = recap['rangeEnd'] as String?;
    final label =
        (rangeEnd != null && rangeEnd != day) ? '$day to $rangeEnd' : day;
    final shareText = StringBuffer('$label recap\n');
    for (final r in rows) {
      shareText.writeln(
          '${r['name']}: ${r['plates']}x - PHP${(r['sales'] as num).toStringAsFixed(0)}');
    }
    shareText.writeln('Total: PHP${sales.toStringAsFixed(0)} / profit PHP${profit.toStringAsFixed(0)}');

    return Card(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      color: Colors.indigo.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.history_edu, size: 18, color: Colors.indigo),
              const SizedBox(width: 6),
              Expanded(
                child: Text('$label: $plates plates · +PHP${profit.toStringAsFixed(0)} profit',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.indigo.shade900)),
              ),
            ]),
            const SizedBox(height: 4),
            for (final r in rows.take(3))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text('${r['plates']}x ${r['name']}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton.icon(
                onPressed: () => Share.share(shareText.toString(), subject: 'TalaKo Day Recap'),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.indigo.shade900),
                icon: const Icon(Icons.share, size: 16),
                label: const Text('Share'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.indigo),
                onPressed: onDismiss,
                child: const Text('Got it',
                    style: TextStyle(color: Colors.white)),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final Dish dish;
  final int servedToday;
  final int servedWeek;
  final bool isBestSeller;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _MenuCard({
    required this.dish,
    required this.servedToday,
    required this.servedWeek,
    required this.isBestSeller,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 5, color: Colors.teal),
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
                  if (servedToday > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('sold ${servedToday}x today',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.teal)),
                    )
                  else if (servedWeek > 0)
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
