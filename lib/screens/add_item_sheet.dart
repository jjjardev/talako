import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/stock_enums.dart';
import '../providers/inventory_provider.dart';

class AddItemSheet extends StatefulWidget {
  const AddItemSheet({super.key});

  @override
  State<AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<AddItemSheet> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  UsageType _usageType = UsageType.retailOnly;
  bool _perishable = false;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final price = double.tryParse(_priceController.text.trim()) ?? 0;
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter item name')));
      return;
    }
    if (_usageType != UsageType.ingredientOnly && price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a selling price above 0')));
      return;
    }
    setState(() => _saving = true);
    final error = await context.read<InventoryProvider>().addItem(
          name: name,
          price: price,
          usageType: _usageType,
          perishable: _perishable,
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
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.add_circle_outline),
              const SizedBox(width: 8),
              const Text('Add Item',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Item name',
              border: OutlineInputBorder(),
            ),
          ),
          if (_usageType != UsageType.ingredientOnly) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _priceController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Selling Price (₱)',
                prefixText: '₱ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            const SizedBox(height: 4),
            Text('Not sold directly - no selling price needed.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
          ],
          SegmentedButton<UsageType>(
            segments: const [
              ButtonSegment(value: UsageType.retailOnly, label: Text('Retail')),
              ButtonSegment(value: UsageType.ingredientOnly, label: Text('Ingredient')),
              ButtonSegment(value: UsageType.both, label: Text('Both')),
            ],
            selected: {_usageType},
            onSelectionChanged: (s) => setState(() => _usageType = s.first),
          ),
          if (_usageType != UsageType.retailOnly) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Perishable'),
              subtitle: const Text('Spoils - tracked by freshness'),
              value: _perishable || _usageType == UsageType.ingredientOnly,
              onChanged: _usageType == UsageType.ingredientOnly
                  ? null
                  : (v) => setState(() => _perishable = v),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save Item', style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
