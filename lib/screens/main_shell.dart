import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'collections_screen.dart';
import 'settings_screen.dart';
import 'stock_home_screen.dart';
import 'add_item_sheet.dart';
import 'add_credit_sheet.dart';
import '../providers/transactions_provider.dart';
import '../providers/inventory_provider.dart';
import '../utils/backup_service.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  final ValueNotifier<StockSegment> _stockSegment =
      ValueNotifier<StockSegment>(StockSegment.shelf);
  bool _showBackupBanner = false;

  @override
  void initState() {
    super.initState();
    BackupService.shouldShowBanner().then((show) {
      if (mounted && show) setState(() => _showBackupBanner = true);
    });
  }

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
      body: Column(
        children: [
          if (_showBackupBanner)
            MaterialBanner(
              content: const Text(
                  'No recent backup. Export one to keep your data safe.'),
              leading: const Icon(Icons.backup_outlined),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _currentIndex = 2;
                      _showBackupBanner = false;
                    });
                  },
                  child: const Text('Open Backup'),
                ),
                TextButton(
                  onPressed: () async {
                    await BackupService.dismissBanner();
                    if (mounted) setState(() => _showBackupBanner = false);
                  },
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          Expanded(child: _screens[_currentIndex]),
        ],
      ),
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
      return FloatingActionButton(
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
    }
    return null;
  }
}
