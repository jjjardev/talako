import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/item.dart';
import '../models/stock_enums.dart';
import '../providers/inventory_provider.dart';

class StockWatchScreen extends StatefulWidget {
  const StockWatchScreen({super.key});

  @override
  State<StockWatchScreen> createState() => _StockWatchScreenState();
}

class _StockWatchScreenState extends State<StockWatchScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InventoryProvider>().loadInventory();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InventoryProvider>(
      builder: (context, inv, _) {
        final items = inv.filteredItems;
        return Column(
          children: [
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: [
                  for (final f in StockFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(switch (f) {
                          StockFilter.all => 'All',
                          StockFilter.retail => 'Retail',
                          StockFilter.ingredients => 'Ingredients',
                          StockFilter.lowOrOut => 'Low / Out',
                          StockFilter.cold => 'Cold',
                        }),
                        selected: inv.filter == f,
                        onSelected: (_) => inv.setFilter(f),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? _emptyState(inv)
                  : RefreshIndicator(
                      onRefresh: () => inv.loadInventory(),
                      child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(10, 4, 10, 90),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 0.92,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, i) =>
                            _ItemCard(item: items[i], onEdit: () => _openEditor(context, items[i])),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _emptyState(InventoryProvider inv) {
    if (inv.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            inv.filter == StockFilter.all
                ? 'Your shelf is empty.\nTap + to add items you sell.'
                : 'No items match this filter.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  void _openEditor(BuildContext context, Item item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ItemEditorSheet(item: item),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final Item item;
  final VoidCallback onEdit;

  const _ItemCard({required this.item, required this.onEdit});

  bool _isIngredientView(Item item) => item.isIngredient;

  @override
  Widget build(BuildContext context) {
    final inv = context.read<InventoryProvider>();
    final badges = inv.badges[item.id] ?? const <ItemBadge>{};
    // Ingredient-only cards cycle freshness; retail cycles stock status.
    final statusColor = _isIngredientView(item) && item.usageType == UsageType.ingredientOnly
        ? item.freshnessStatus.color
        : item.stockStatus.color;
    final statusLabel = _isIngredientView(item) && item.usageType == UsageType.ingredientOnly
        ? item.freshnessStatus.label
        : item.stockStatus.label;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () {
          final inv = context.read<InventoryProvider>();
          if (_isIngredientView(item) && item.usageType == UsageType.ingredientOnly) {
            inv.cycleFreshness(item.id!);
          } else {
            inv.cycleStockStatus(item.id!);
          }
        },
        onLongPress: onEdit,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 5, color: statusColor),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (item.usageType != UsageType.retailOnly)
                        Icon(item.usageType.icon, size: 14, color: Colors.grey),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Icon(Icons.circle, size: 10, color: statusColor),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          statusLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  if (badges.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        for (final b in badges.take(3))
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(b.icon, size: 14, color: b.color),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemEditorSheet extends StatefulWidget {
  final Item item;

  const _ItemEditorSheet({required this.item});

  @override
  State<_ItemEditorSheet> createState() => _ItemEditorSheetState();
}

class _ItemEditorSheetState extends State<_ItemEditorSheet> {
  late UsageType _usageType = widget.item.usageType;
  late bool _perishable = widget.item.perishable;
  late final TextEditingController _notes =
      TextEditingController(text: widget.item.notes ?? '');
  late final TextEditingController _price =
      TextEditingController(text: widget.item.price.toString());

  @override
  void dispose() {
    _notes.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final price = double.tryParse(_price.text.trim()) ?? widget.item.price;
    await context.read<InventoryProvider>().updateItem(widget.item.copyWith(
          price: price <= 0 ? null : price,
          usageType: _usageType,
          perishable: _perishable || _usageType == UsageType.ingredientOnly,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          clearNotes: _notes.text.trim().isEmpty,
        ));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('"${widget.item.name}" will be removed from your shelf and any dishes using it will lose this ingredient.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<InventoryProvider>().deleteItem(widget.item.id!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.item.name,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Price (₱)',
                prefixText: '₱ ',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<UsageType>(
              segments: const [
                ButtonSegment(value: UsageType.retailOnly, label: Text('Retail')),
                ButtonSegment(value: UsageType.ingredientOnly, label: Text('Ingredient')),
                ButtonSegment(value: UsageType.both, label: Text('Both')),
              ],
              selected: {_usageType},
              onSelectionChanged: (s) => setState(() {
                _usageType = s.first;
                if (_usageType == UsageType.ingredientOnly) _perishable = true;
              }),
            ),
            if (_usageType != UsageType.ingredientOnly)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Perishable'),
                value: _perishable,
                onChanged: (v) => setState(() => _perishable = v),
              ),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: '"Buy from Aling Nena, cheaper"',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                  child: const Text('Save'),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
