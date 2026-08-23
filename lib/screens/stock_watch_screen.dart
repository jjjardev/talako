import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/item.dart';
import '../models/stock_enums.dart';
import '../providers/inventory_provider.dart';
import '../widgets/alphabet_strip.dart';

class StockWatchScreen extends StatefulWidget {
  const StockWatchScreen({super.key});

  @override
  State<StockWatchScreen> createState() => _StockWatchScreenState();
}

class _StockWatchScreenState extends State<StockWatchScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

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
                      child: LayoutBuilder(
                        builder: (context, cons) {
                          final sorted = [...items]
                            ..sort((a, b) => a.name
                                .toLowerCase()
                                .compareTo(b.name.toLowerCase()));
                          final offsets =
                              AlphabetStrip.letterOffsets(sorted.map((i) => i.name).toList());
                          return Stack(
                            children: [
                              GridView.builder(
                                controller: _scroll,
                                padding:
                                    const EdgeInsets.fromLTRB(10, 4, 30, 90),
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 145,
                                  mainAxisSpacing: 6,
                                  crossAxisSpacing: 6,
                                  childAspectRatio: 0.95,
                                ),
                                itemCount: sorted.length,
                                itemBuilder: (context, i) => _ItemCard(
                                    item: sorted[i],
                                    onEdit: () =>
                                        _openEditor(context, sorted[i])),
                              ),
                              Positioned(
                                right: 2,
                                top: 0,
                                bottom: 90,
                                child: Center(
                                  child: AlphabetStrip(
                                    letters: offsets.keys.toList(),
                                    onLetter: (l) {
                                      final target = AlphabetStrip
                                          .gridScrollOffsetFor(
                                        itemIndex: offsets[l]!,
                                        availableWidth: cons.maxWidth,
                                        horizontalPadding: 40,
                                        maxCrossAxisExtent: 145,
                                        crossAxisSpacing: 6,
                                        mainAxisSpacing: 6,
                                        childAspectRatio: 0.95,
                                        leadingVerticalInset: 4,
                                      );
                                      _scroll.animateTo(
                                        target.clamp(0.0,
                                            _scroll.position.maxScrollExtent),
                                        duration:
                                            const Duration(milliseconds: 250),
                                        curve: Curves.easeInOut,
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
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

  @override
  Widget build(BuildContext context) {
    final inv = context.read<InventoryProvider>();
    final badges = inv.badges[item.id] ?? const <ItemBadge>{};
    final statusColor = item.stockStatus.color;
    final statusLabel = item.stockStatus.label;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () =>
            context.read<InventoryProvider>().cycleStockStatus(item.id!),
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

Widget _statusChip(String label, Color color, String hint) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.circle, size: 9, color: color),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
      const SizedBox(width: 6),
      Text(hint, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
    ]),
  );
}

class _ItemEditorSheet extends StatefulWidget {
  final Item item;

  const _ItemEditorSheet({required this.item});

  @override
  State<_ItemEditorSheet> createState() => _ItemEditorSheetState();
}

class _ItemEditorSheetState extends State<_ItemEditorSheet> {
  late UsageType _usageType = widget.item.usageType;
  late StockStatus _stockStatus = widget.item.stockStatus;
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
          stockStatus: _stockStatus,
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
            if (_usageType == UsageType.ingredientOnly) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('Not sold directly - no selling price needed.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              ),
            ] else ...[
              const SizedBox(height: 12),
              TextField(
                controller: _price,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Selling Price (₱)',
                  prefixText: '₱ ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SegmentedButton<UsageType>(
              segments: const [
                ButtonSegment(value: UsageType.retailOnly, label: Text('Retail')),
                ButtonSegment(value: UsageType.ingredientOnly, label: Text('Ingredient')),
                ButtonSegment(value: UsageType.both, label: Text('Both')),
              ],
              selected: {_usageType},
              onSelectionChanged: (s) =>
                  setState(() => _usageType = s.first),
            ),
            const SizedBox(height: 6),
            Row(children: [
              const SizedBox(
                  width: 92,
                  child: Text('Shelf:', style: TextStyle(fontSize: 13))),
              Expanded(
                child: GestureDetector(
                  onTap: () =>
                      setState(() => _stockStatus = _stockStatus.next()),
                  child: _statusChip(_stockStatus.label, _stockStatus.color,
                      'tap to change'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
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
