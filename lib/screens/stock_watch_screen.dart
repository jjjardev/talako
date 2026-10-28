import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/item.dart';
import '../models/stock_enums.dart';
import '../providers/inventory_provider.dart';
import '../utils/currency_format.dart';
import '../utils/money.dart';
import '../utils/snackbars.dart';
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
        final showAzStrip = true; // always show A-Z for findability, even in urgent
        final lowOutCount = inv.shoppingList.length;
        final coldCount = inv.items
            .where((i) => i.stockStatus == StockStatus.cold)
            .length;
        final collapsedFilters = [
          StockFilter.all,
          StockFilter.lowOrOut,
          StockFilter.cold,
        ];
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      children: [
                        for (final f in collapsedFilters)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(switch (f) {
                                StockFilter.all => 'All',
                                StockFilter.lowOrOut => 'Low / Out ($lowOutCount)',
                                StockFilter.cold => 'Archived ($coldCount)',
                                _ => 'Retail',
                              }),
                              selected: inv.filter == f,
                              onSelected: (_) => inv.setFilter(f),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<StockFilter>(
                  tooltip: 'More filters',
                  icon: Icon(
                    Icons.filter_alt_outlined,
                    color: inv.filter == StockFilter.retail ||
                            inv.filter == StockFilter.ingredients
                        ? Colors.teal.shade700
                        : null,
                  ),
                  onSelected: inv.setFilter,
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                        value: StockFilter.retail, child: Text('Retail items')),
                    PopupMenuItem(
                        value: StockFilter.ingredients,
                        child: Text('Ingredients')),
                  ],
                ),
                Tooltip(
                  message: inv.sort == ShelfSort.alpha
                      ? 'Sorted: A to Z'
                      : 'Sorted: urgent first',
                  child: IconButton(
                    tooltip: 'Toggle sort',
                    onPressed: () => context
                        .read<InventoryProvider>()
                        .setSort(inv.sort == ShelfSort.alpha
                            ? ShelfSort.urgent
                            : ShelfSort.alpha),
                    icon: Icon(
                      inv.sort == ShelfSort.alpha
                          ? Icons.sort_by_alpha
                          : Icons.low_priority,
                      color: Colors.teal.shade700,
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: items.isEmpty
                  ? _emptyState(inv)
                  : RefreshIndicator(
                      onRefresh: () => inv.loadInventory(),
                      child: LayoutBuilder(
                        builder: (context, cons) {
                          final sorted = items;
                          final offsets = inv.sort == ShelfSort.alpha
                              ? AlphabetStrip.letterOffsets(
                                  sorted.map((i) => i.name).toList())
                              : const <String, int>{};
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
                                  onEdit: () => _openEditor(context, sorted[i]),
                                  onQuickActions: () =>
                                      _openQuickActions(context, sorted[i]),
                                ),
                              ),
                              if (showAzStrip)
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
          if (inv.filter != StockFilter.all) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.teal),
              icon: const Icon(Icons.filter_alt_off, size: 18),
              label: const Text('Clear filter'),
              onPressed: () => inv.setFilter(StockFilter.all),
            ),
          ],
        ],
      ),
    );
  }

  void _openQuickActions(BuildContext context, Item item) {
    final inv = context.read<InventoryProvider>();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(item.name,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            for (final status in [
              StockStatus.wellStocked,
              StockStatus.runningLow,
              StockStatus.outOfStock
            ])
              ListTile(
                dense: true,
                leading: Icon(Icons.circle,
                    size: 12, color: status.color),
                title: Text(status.label),
                trailing: item.stockStatus == status
                    ? const Icon(Icons.check, size: 18, color: Colors.teal)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  inv.setStockStatus(item.id!, status);
                },
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.restore,
                  size: 20, color: Colors.teal),
              title: const Text('Restocked - back to Well Stocked'),
              subtitle: const Text('Marks bought and stamps the date'),
              onTap: () {
                Navigator.pop(ctx);
                inv.restock([item.id!]);
              },
            ),
            ListTile(
              leading: Icon(Icons.archive_outlined,
                  size: 20, color: StockStatus.cold.color),
              title: Text(StockStatus.cold.label),
              subtitle: const Text('Hidden from Shopping — for discontinued items'),
              trailing: item.stockStatus == StockStatus.cold
                  ? const Icon(Icons.check, size: 18, color: Colors.teal)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                inv.setStockStatus(item.id!, StockStatus.cold);
              },
            ),
            ListTile(
              leading: const Icon(Icons.remove_shopping_cart_outlined,
                  size: 20, color: Colors.orange),
              title: const Text('Log loss / spoilage'),
              subtitle: const Text('Records a loss and marks the item Out'),
              onTap: () {
                Navigator.pop(ctx);
                _logLoss(context, item);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.edit_outlined, size: 20),
              title: const Text('Edit details'),
              onTap: () {
                Navigator.pop(ctx);
                _openEditor(context, item);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logLoss(BuildContext context, Item item) async {
    final value = TextEditingController(
        text: item.price > 0 ? formatMinorPlain(item.price) : '');
    final note = TextEditingController();
    final inv = context.read<InventoryProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Log loss: ${item.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: value,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Estimated value (₱)',
                prefixText: '₱ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: note,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Log loss')),
        ],
      ),
    );
    final minor = parseMajorToMinor(value.text) ?? 0;
    final noteText = note.text.trim();
    value.dispose();
    note.dispose();
    if (confirmed != true) return;
    if (minor <= 0) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Enter the estimated value')));
      return;
    }
    await inv.logSpoilage(item.id!, minor, noteText.isEmpty ? null : noteText);
    messenger.showSnackBar(SnackBar(content: Text('Loss logged for ${item.name}')));
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
  final VoidCallback onQuickActions;

  const _ItemCard({
    required this.item,
    required this.onEdit,
    required this.onQuickActions,
  });

  String _stampHint() {
    final iso = item.lastStatusUpdated ?? item.lastRestocked;
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso);
      final days = DateTime.now().difference(dt).inDays;
      if (days <= 0) return '• today';
      if (days == 1) return '• 1d ago';
      return '• ${days}d ago';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = item.stockStatus.color;
    final statusLabel = item.stockStatus.label;
    final showPrice = item.usageType != UsageType.ingredientOnly;
    final stamp = _stampHint();

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () async {
          HapticFeedback.selectionClick();
          final prev = item.stockStatus;
          final next = prev.next();
          await context.read<InventoryProvider>().cycleStockStatus(item.id!);
          if (!context.mounted) return;
          showAutoDismissSnackBar(
            ScaffoldMessenger.of(context),
            message: '${item.name} → ${next.label}',
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => context.read<InventoryProvider>().setStockStatus(item.id!, prev),
            ),
          );
        },
        onLongPress: onQuickActions,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 5, color: statusColor),
            Expanded(
              child: Padding(
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
                    if (showPrice) ...[
                      const SizedBox(height: 2),
                      Text(
                        formatCurrency(item.price),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                    const Spacer(),
                    Row(
                      children: [
                        Icon(Icons.circle, size: 10, color: statusColor),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            stamp.isEmpty ? statusLabel : '$statusLabel $stamp',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.touch_app, size: 10, color: Colors.grey.shade400),
                        const SizedBox(width: 3),
                        Text('Tap to cycle',
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                      ],
                    ),
                  ],
                ),
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
  late final TextEditingController _name =
      TextEditingController(text: widget.item.name);
  late final TextEditingController _notes =
      TextEditingController(text: widget.item.notes ?? '');
  late final TextEditingController _price =
      TextEditingController(text: formatMinorPlain(widget.item.price));
  String? _nameError;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newName = _name.text.trim();
    if (newName.isEmpty) {
      setState(() => _nameError = 'Name cannot be empty');
      return;
    }
    setState(() {
      _saving = true;
      _nameError = null;
    });
    final price = parseMajorToMinor(_price.text.trim()) ?? widget.item.price;
    final statusChanged = _stockStatus != widget.item.stockStatus;
    final nowIso = statusChanged ? DateTime.now().toIso8601String() : null;
    final error = await context.read<InventoryProvider>().updateItem(
          widget.item.copyWith(
            name: newName,
            price: price <= 0 ? null : price,
            usageType: _usageType,
            stockStatus: _stockStatus,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            clearNotes: _notes.text.trim().isEmpty,
            lastStatusUpdated: nowIso,
            lastRestocked: (_stockStatus == StockStatus.wellStocked && statusChanged) ? nowIso : null,
          ),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      setState(() => _nameError = error);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
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
            Row(
              children: [
                const Icon(Icons.edit_outlined, size: 20, color: Colors.teal),
                const SizedBox(width: 8),
                const Text('Edit Item',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Item name',
                border: const OutlineInputBorder(),
                isDense: true,
                errorText: _nameError,
                prefixIcon: const Icon(Icons.label_outline, size: 20),
              ),
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
            const SizedBox(height: 4),
            Text(
              'Renaming only changes the shelf. Past receipts keep the old name for audit.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
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
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save'),
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
