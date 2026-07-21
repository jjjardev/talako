import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../models/credit_entry.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';

class CreditTile extends StatelessWidget {
  final CreditEntry entry;
  final VoidCallback onPayFull;
  final VoidCallback onPayPartial;

  const CreditTile({
    super.key,
    required this.entry,
    required this.onPayFull,
    required this.onPayPartial,
  });

  static const _settledColor = Color(0x144CAF50);

  @override
  Widget build(BuildContext context) {
    final remaining = entry.remaining;
    final settled = entry.isSettled;
    return Slidable(
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        children: [
          if (!settled)
            SlidableAction(
              onPressed: (_) => onPayFull(),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              icon: Icons.payments,
              label: 'Pay Full',
            ),
        ],
      ),
      child: Card(
        color: settled ? _settledColor : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.itemName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: settled ? Colors.green : Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      settled ? 'Paid' : 'Unsettled',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('${entry.quantity} × ${formatCurrency(entry.pricePerUnit)} = ${formatCurrency(entry.total)}'),
              Text(formatDate(entry.timestamp), style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              if (!settled) ...[
                const SizedBox(height: 4),
                Text('Remaining: ${formatCurrency(remaining)}', style: const TextStyle(color: Colors.red)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: onPayPartial,
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Partial'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
