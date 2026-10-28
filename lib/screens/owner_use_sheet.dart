import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_provider.dart';
import '../utils/currency_format.dart';
import '../utils/snackbars.dart';
import '../utils/money.dart';

/// Quick-action sheet for logging personal consumption ("panty" problem).
class OwnerUseSheet extends StatefulWidget {
  const OwnerUseSheet({super.key});

  @override
  State<OwnerUseSheet> createState() => _OwnerUseSheetState();
}

class _OwnerUseSheetState extends State<OwnerUseSheet> {
  int? _selectedItemId;
  late final TextEditingController _value = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selectedItemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pick an item')));
      return;
    }
    final value = parseMajorToMinor(_value.text.trim()) ?? 0;
    if (value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter the estimated value')));
      return;
    }
    setState(() => _saving = true);
    final inv = context.read<InventoryProvider>();
    final item = inv.itemById(_selectedItemId!);
    if (item == null) return;
    final ok = await inv.recordOwnerUse([
      {
        'item_name': item.name,
        'quantity': 1,
        'price': value,
        'subtotal': value,
      }
    ]);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to record - try again')));
      return;
    }
    // Capture before popping - a dismissed sheet's context is unusable.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    showAutoDismissSnackBar(
      messenger,
      message: 'Personal use recorded (${formatCurrency(value)})',
    );
  }

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
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
              const Icon(Icons.takeout_dining_outlined),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Personal use',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 4),
          Text('Logged separately - never counts as sales or debt.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _selectedItemId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Item',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final item in inv.items)
                DropdownMenuItem(value: item.id, child: Text(item.name)),
            ],
            onChanged: (id) {
              setState(() {
                _selectedItemId = id;
                final item = inv.itemById(id!);
                if (item != null && _value.text.isEmpty) {
                  _value.text = formatMinorPlain(item.price);
                }
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _value,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Estimated value (₱)',
              prefixText: '₱ ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.teal),
              onPressed: _saving ? null : _save,
              child: const Text('Record Personal Use'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
