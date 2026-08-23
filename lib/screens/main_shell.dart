import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'collections_screen.dart';
import 'settings_screen.dart';
import 'stock_home_screen.dart';
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

  static const _screens = <Widget>[
    CollectionsScreen(),
    StockHomeScreen(),
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
      floatingActionButton: _buildFab(context),
    );
  }

  Widget? _buildFab(BuildContext context) {
    if (_currentIndex == 0) {
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
    if (_currentIndex == 1) {
      return FloatingActionButton(
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
    }
    return null;
  }
}
