import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/stock_enums.dart';
import '../providers/inventory_provider.dart';
import '../utils/money.dart';

class AddItemSheet extends StatefulWidget {
  const AddItemSheet({super.key});

  @override
  State<AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<AddItemSheet> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  bool _notSoldDirectly = false;
  StockStatus _stockStatus = StockStatus.wellStocked;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final price = parseMajorToMinor(_priceController.text.trim()) ?? 0;
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter item name')));
      return;
    }
    if (!_notSoldDirectly && price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a selling price above 0')));
      return;
    }
    setState(() => _saving = true);
    final error = await context.read<InventoryProvider>().addItem(
          name: name,
          price: price,
          usageType:
              _notSoldDirectly ? UsageType.ingredientOnly : UsageType.retailOnly,
          stockStatus: _stockStatus,
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
      child: SingleChildScrollView(
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
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Not sold directly (ingredient)'),
            value: _notSoldDirectly,
            onChanged: (v) => setState(() => _notSoldDirectly = v ?? false),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const SizedBox(width: 48, child: Text('Shelf:', style: TextStyle(fontSize: 13))),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _stockStatus = _stockStatus.next()),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    decoration: BoxDecoration(
                      color: _stockStatus.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _stockStatus.color),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.circle, size: 9, color: _stockStatus.color),
                      const SizedBox(width: 6),
                      Text(_stockStatus.label,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _stockStatus.color)),
                      const SizedBox(width: 6),
                      Text('tap to change', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ]),
                  ),
                ),
              ),
            ],
          ),
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
      ),
    );
  }
}
