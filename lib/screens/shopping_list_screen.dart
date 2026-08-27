import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/item.dart';
import '../models/stock_enums.dart';
import '../providers/inventory_provider.dart';

class ShoppingListScreen extends StatelessWidget {
  const ShoppingListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    final items = inv.shoppingList;

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_basket_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Nothing needed right now.\nMark items Low or Out on your Shelf scan\nand they will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<InventoryProvider>().loadInventory(),
      child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
          if (items.isNotEmpty) ...[
            _sectionHeader('Running Low / Out of Stock', Icons.storefront),
            for (final item in items)
              _RestockRow(item: item, statusLabel: item.stockStatus.label, statusColor: item.stockStatus.color),
          ],

        if (items.isNotEmpty) ...[
          const SizedBox(height: 8),
          Center(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.teal),
              icon: const Icon(Icons.share, size: 18),
              label: const Text('Share List'),
              onPressed: () => shareShoppingList(inv),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.teal),
          const SizedBox(width: 6),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      ),
    );
  }
}

/// Shared with StockHomeScreen's AppBar so it is reachable from any state.
void shareShoppingList(InventoryProvider inv) {
  final items = inv.shoppingList;
  final buffer = StringBuffer('SHOPPING LIST\n==============\n');
  if (items.isNotEmpty) {
    buffer.writeln('\nNEEDED:');
    for (final i in items) {
      buffer.writeln('- ${i.name} (${i.stockStatus.label})');
    }
  }
  Share.share(buffer.toString(), subject: 'TalaKo Shopping List');
}

class _RestockRow extends StatefulWidget {
  final Item item;
  final String statusLabel;
  final Color statusColor;

  const _RestockRow({
    required this.item,
    required this.statusLabel,
    required this.statusColor,
  });

  @override
  State<_RestockRow> createState() => _RestockRowState();
}

class _RestockRowState extends State<_RestockRow> {
  bool _bought = false;

  Future<void> _markBought(bool? value) async {
    setState(() => _bought = value ?? false);
    if (!_bought) return;
    await context.read<InventoryProvider>().restock([widget.item.id!]);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${widget.item.name} marked as bought'),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.item.notes;
    return CheckboxListTile(
      value: _bought,
      onChanged: _markBought,
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(
        widget.item.name,
        style: TextStyle(
          decoration: _bought ? TextDecoration.lineThrough : null,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle, size: 9, color: widget.statusColor),
              const SizedBox(width: 4),
              Text(widget.statusLabel,
                  style: TextStyle(fontSize: 12, color: widget.statusColor, fontWeight: FontWeight.w600)),
            ],
          ),
          if (notes != null && notes.isNotEmpty)
            Text(notes, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}
