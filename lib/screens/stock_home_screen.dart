import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'shopping_list_screen.dart';
import 'stock_watch_screen.dart';
import '../providers/inventory_provider.dart';

/// Which view is active inside the Stock tab.
enum StockSegment { shelf, shopping }

class StockHomeScreen extends StatelessWidget {
  final ValueNotifier<StockSegment> segment;

  const StockHomeScreen({super.key, required this.segment});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock'),
        centerTitle: true,
        actions: [
          ValueListenableBuilder<StockSegment>(
            valueListenable: segment,
            builder: (context, s, _) => s == StockSegment.shopping
                ? IconButton(
                    tooltip: 'Share list',
                    icon: const Icon(Icons.share),
                    onPressed: () => shareShoppingList(
                        context.read<InventoryProvider>()),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Consumer<InventoryProvider>(
              builder: (context, inv, _) {
                final shoppingCount = inv.shoppingList.length;
                return ValueListenableBuilder<StockSegment>(
                  valueListenable: segment,
                  builder: (context, s, _) => SegmentedButton<StockSegment>(
                    segments: [
                      const ButtonSegment(value: StockSegment.shelf, label: Text('Shelf')),
                      ButtonSegment(
                          value: StockSegment.shopping,
                          label: Text(shoppingCount > 0 ? 'Shopping ($shoppingCount)' : 'Shopping')),
                    ],
                    selected: {s},
                    onSelectionChanged: (sel) => segment.value = sel.first,
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<StockSegment>(
              valueListenable: segment,
              builder: (context, s, _) => switch (s) {
                StockSegment.shelf => const StockWatchScreen(),
                StockSegment.shopping => const ShoppingListScreen(),
              },
            ),
          ),
        ],
      ),
    );
  }
}
