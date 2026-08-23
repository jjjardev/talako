import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/dish.dart';
import '../models/stock_enums.dart';
import '../widgets/alphabet_strip.dart';
import '../providers/inventory_provider.dart';

class AddEditDishScreen extends StatefulWidget {
  final DishWithIngredients? existing;

  const AddEditDishScreen({super.key, this.existing});

  @override
  State<AddEditDishScreen> createState() => _AddEditDishScreenState();
}

class _AddEditDishScreenState extends State<AddEditDishScreen> {
  final _formKey = GlobalKey<FormState>();
  final ScrollController _pickerScroll = ScrollController();
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.dish.name ?? '');
  late final TextEditingController _price = TextEditingController(
      text: widget.existing == null ? '' : widget.existing!.dish.price.toString());
  late final TextEditingController _capital = TextEditingController(
      text: widget.existing == null || widget.existing!.dish.capital == 0
          ? ''
          : widget.existing!.dish.capital.toString());
  late final Set<int> _ingredientIds =
      widget.existing?.ingredients.map((i) => i.itemId).toSet() ?? <int>{};
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _capital.dispose();
    _pickerScroll.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final error = await context.read<InventoryProvider>().saveDish(
          dishId: widget.existing?.dish.id,
          name: _name.text.trim(),
          price: double.tryParse(_price.text.trim()) ?? 0,
          capital: double.tryParse(_capital.text.trim()) ?? 0,
          ingredientIds: _ingredientIds.toList(),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Add Dish' : 'Edit Dish'),
        centerTitle: true,
        actions: [
          if (widget.existing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete dish?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Delete', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirmed != true || !context.mounted) return;
                await context.read<InventoryProvider>().deleteDish(widget.existing!.dish.id!);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Dish name',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Selling Price (₱)',
                prefixText: '₱ ',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final p = double.tryParse(v ?? '');
                if (p == null || p <= 0) return 'Enter a price above 0';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _capital,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Cost / Puhunan per plate (₱)',
                prefixText: '₱ ',
                border: OutlineInputBorder(),
                helperText: 'Your estimated cost - drives the margin shown on every sale',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null; // optional
                final c = double.tryParse(v.trim());
                if (c == null) return 'Enter a valid amount';
                final p = double.tryParse(_price.text.trim()) ?? 0;
                if (c >= p) return 'Puhunan must be below the selling price';
                return null;
              },
            ),
            const SizedBox(height: 20),
            Text('Ingredients',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('This dish is available when no ingredient is Empty / Spoiled.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, cons) {
                final available = inv.items.where((i) => i.isIngredient).toList()
                  ..sort((a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                if (available.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'No ingredients yet - mark items as Ingredient or Both first (Shelf tab, long-press an item).',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  );
                }
                final offsets = AlphabetStrip.letterOffsets(available.map((i) => i.name).toList());
                return SizedBox(
                  height: 260,
                  child: Stack(
                    children: [
                      GridView.builder(
                        controller: _pickerScroll,
                        padding: const EdgeInsets.only(right: 26, top: 2, bottom: 2),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 150,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                          childAspectRatio: 2.6,
                        ),
                        itemCount: available.length,
                        itemBuilder: (context, i) {
                          final item = available[i];
                          final selected =
                              item.id != null && _ingredientIds.contains(item.id);
                          return InkWell(
                            onTap: () => setState(() {
                              selected
                                  ? _ingredientIds.remove(item.id)
                                  : _ingredientIds.add(item.id!);
                            }),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selected
                                      ? Colors.teal
                                      : Colors.grey.shade400,
                                  width: selected ? 2 : 1,
                                ),
                                color: selected
                                    ? Colors.teal.withValues(alpha: 0.12)
                                    : null,
                              ),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                children: [
                                  Icon(Icons.circle,
                                      size: 8, color: item.freshnessStatus.color),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(item.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13)),
                                  ),
                                  if (selected)
                                    const Icon(Icons.check_circle,
                                        size: 16, color: Colors.teal),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: AlphabetStrip(
                            letters: offsets.keys.toList(),
                            onLetter: (l) {
                              final target = AlphabetStrip.gridScrollOffsetFor(
                                itemIndex: offsets[l]!,
                                availableWidth: cons.maxWidth,
                                horizontalPadding: 26,
                                maxCrossAxisExtent: 150,
                                crossAxisSpacing: 6,
                                mainAxisSpacing: 6,
                                childAspectRatio: 2.6,
                                leadingVerticalInset: 2,
                              );
                              _pickerScroll.animateTo(
                                target.clamp(0.0,
                                    _pickerScroll.position.maxScrollExtent),
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            for (final id in _ingredientIds)
              if (inv.itemById(id) != null)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading:
                      Icon(Icons.circle, size: 10, color: inv.itemById(id)!.freshnessStatus.color),
                  title: Text(inv.itemById(id)!.name),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _ingredientIds.remove(id)),
                  ),
                ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                onPressed: _saving ? null : _save,
                child: Text(widget.existing == null ? 'Save Dish' : 'Update Dish'),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '${_ingredientIds.length} ingredients',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
