import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/dish.dart';
import '../providers/inventory_provider.dart';

class AddEditDishScreen extends StatefulWidget {
  final Dish? existing;

  const AddEditDishScreen({super.key, this.existing});

  @override
  State<AddEditDishScreen> createState() => _AddEditDishScreenState();
}

class _AddEditDishScreenState extends State<AddEditDishScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _price = TextEditingController(
      text:
          widget.existing == null ? '' : widget.existing!.price.toString());
  late final TextEditingController _capital = TextEditingController(
      text: widget.existing == null || widget.existing!.capital == 0
          ? ''
          : widget.existing!.capital.toString());
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _capital.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final error = await context.read<InventoryProvider>().saveDish(
          dishId: widget.existing?.id,
          name: _name.text.trim(),
          price: double.tryParse(_price.text.trim()) ?? 0,
          capital: double.tryParse(_capital.text.trim()) ?? 0,
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
                await context
                    .read<InventoryProvider>()
                    .deleteDish(widget.existing!.id!);
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
                if (p == null || p <= 0) return 'Enter a selling price above 0';
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
                helperText:
                    'Your estimated cost - drives the margin shown on every sale',
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
            SizedBox(
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                onPressed: _saving ? null : _save,
                child: Text(widget.existing == null ? 'Save Dish' : 'Update Dish'),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'Tip: keep cost below price so every plate earns.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
