import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'collections_screen.dart';
import 'settings_screen.dart';
import 'stock_home_screen.dart';
import 'add_edit_dish_screen.dart';
import 'add_item_sheet.dart';
import 'add_credit_sheet.dart';
import '../providers/transactions_provider.dart';
import '../providers/inventory_provider.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  final ValueNotifier<StockSegment> _stockSegment =
      ValueNotifier<StockSegment>(StockSegment.shelf);

  @override
  void dispose() {
    _stockSegment.dispose();
    super.dispose();
  }

  late final List<Widget> _screens = [
    CollectionsScreen(),
    StockHomeScreen(segment: _stockSegment),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
          if (index == 0) {
            context.read<TransactionsProvider>().loadActiveTransactions();
          } else if (index == 1) {
            context.read<InventoryProvider>().loadInventory();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Credit Book',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Stock',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
      floatingActionButton: _buildFab(context, _currentIndex),
    );
  }

  Widget? _buildFab(BuildContext context, int index) {
    if (index == 0) {
      return FloatingActionButton(
        onPressed: () {
          final provider = context.read<TransactionsProvider>();
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (_) => const AddCreditSheet(),
          ).then((_) {
            provider.loadActiveTransactions();
          });
        },
        child: const Icon(Icons.add),
      );
    }
    if (index == 1) {
      // Context-aware: the + means whatever the current Stock view is about.
      return ValueListenableBuilder<StockSegment>(
        valueListenable: _stockSegment,
        builder: (context, segment, _) {
          if (segment == StockSegment.shopping) return const SizedBox.shrink();
          if (segment == StockSegment.kitchen) {
            return FloatingActionButton.extended(
              heroTag: 'fab_new_dish',
              onPressed: () {
                final inv = context.read<InventoryProvider>();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddEditDishScreen()),
                ).then((_) => inv.loadInventory());
              },
              icon: const Icon(Icons.restaurant_menu),
              label: const Text('New Dish'),
            );
          }
          return FloatingActionButton(
            heroTag: 'fab_add_item',
            tooltip: 'Add item',
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (_) => const AddItemSheet(),
            ),
            child: const Icon(Icons.add),
          );
        },
      );
    }
    return null;
  }
}
