import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/dish.dart';
import '../models/stock_enums.dart';
import '../providers/inventory_provider.dart';

class AddEditDishScreen extends StatefulWidget {
  final DishWithIngredients? existing;

  const AddEditDishScreen({super.key, this.existing});

  @override
  State<AddEditDishScreen> createState() => _AddEditDishScreenState();
}

class _AddEditDishScreenState extends State<AddEditDishScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.dish.name ?? '');
  late final TextEditingController _price = TextEditingController(
      text: widget.existing == null ? '' : widget.existing!.dish.price.toString());
  late final Set<int> _ingredientIds =
      widget.existing?.ingredients.map((i) => i.itemId).toSet() ?? <int>{};
  List<String> _suggestions = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSuggestions());
  }

  Future<void> _loadSuggestions() async {
    final inv = context.read<InventoryProvider>();
    final names = inv.items.map((i) => i.name).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (!mounted) return;
    setState(() => _suggestions = names);
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final error = await context.read<InventoryProvider>().saveDish(
          dishId: widget.existing?.dish.id,
          name: _name.text.trim(),
          price: double.tryParse(_price.text.trim()) ?? 0,
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
                labelText: 'Price (₱)',
                prefixText: '₱ ',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final p = double.tryParse(v ?? '');
                if (p == null || p <= 0) return 'Enter a price above 0';
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
            Autocomplete<String>(
              optionsBuilder: (v) {
                if (v.text.isEmpty) return const Iterable.empty();
                final selectedNames = _ingredientIds
                    .map((id) => inv.itemById(id)?.name ?? '')
                    .toSet();
                return _suggestions.where((s) =>
                    s.toLowerCase().contains(v.text.toLowerCase()) &&
                    !selectedNames.contains(s));
              },
              fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onSubmitted: (_) => onSubmitted(),
                  decoration: const InputDecoration(
                    hintText: 'Search items to add...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                );
              },
              onSelected: (selected) {
                final match = inv.items.firstWhere(
                  (i) => i.name.toLowerCase() == selected.toLowerCase(),
                );
                setState(() => _ingredientIds.add(match.id!));
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
