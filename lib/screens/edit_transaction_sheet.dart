import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/transactions_provider.dart';
import '../utils/currency_format.dart';
import '../utils/money.dart';
import '../utils/snackbars.dart';

class EditTransactionSheet extends StatefulWidget {
  final ActiveTransaction transaction;

  const EditTransactionSheet({super.key, required this.transaction});

  @override
  State<EditTransactionSheet> createState() => _EditTransactionSheetState();
}

class _EditTransactionSheetState extends State<EditTransactionSheet> {
  late final List<_EditLine> _lines = [
    for (final item in widget.transaction.items)
      _EditLine(
        itemName: item.itemName,
        quantity: item.quantity,
        price: item.price,
      ),
  ];
  bool _saving = false;

  bool get _wasTranscribed => widget.transaction.transcribedToBook;

  int get _total {
    var sum = 0;
    for (final line in _lines) {
      sum += line.quantity * line.price;
    }
    return sum;
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.priceController.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final valid = _lines
        .where((line) => line.itemName.trim().isNotEmpty && line.price > 0)
        .toList();
    if (valid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add at least one item')));
      return;
    }
    setState(() => _saving = true);
    final provider = context.read<TransactionsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    await provider.editTransactionItems(
      widget.transaction.id,
      [
        for (final line in valid)
          {
            'item_name': line.itemName.trim(),
            'quantity': line.quantity,
            'price': line.price,
            'subtotal': line.quantity * line.price,
          }
      ],
    );
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context);
    showAutoDismissSnackBar(messenger, message: 'Receipt updated');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
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
                const Expanded(
                  child: Text('Edit receipt',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            if (_wasTranscribed) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: const Text(
                  'This entry is marked as transcribed to your physical book. '
                  'Saving will clear that mark.',
                  style: TextStyle(color: Colors.deepOrange),
                ),
              ),
            ],
            const SizedBox(height: 12),
            for (final line in _lines) _buildLine(line),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total:',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(
                  formatCurrency(_total),
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Save changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLine(_EditLine line) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(line.itemName,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  onPressed: line.quantity > 1
                      ? () => setState(() => line.quantity--)
                      : null,
                ),
                Text('${line.quantity}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  onPressed: () => setState(() => line.quantity++),
                ),
                const Spacer(),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: line.priceController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Price (₱)',
                      prefixText: '₱ ',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      line.price = parseMajorToMinor(v) ?? 0;
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditLine {
  final String itemName;
  int quantity;
  int price;
  final TextEditingController priceController;

  _EditLine({
    required this.itemName,
    required this.quantity,
    required this.price,
  }) : priceController =
            TextEditingController(text: formatMinorPlain(price));
}
