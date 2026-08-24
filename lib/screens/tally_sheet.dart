import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/dish.dart';
import '../providers/inventory_provider.dart';
import '../utils/currency_format.dart';
import '../utils/snackbars.dart';

/// End-of-day tally: the primary way to record menu sales when nobody
/// taps during the rush. One screen, big steppers, one receipt saved.
class TallySheet extends StatefulWidget {
  const TallySheet({super.key});

  @override
  State<TallySheet> createState() => _TallySheetState();
}

class _TallySheetState extends State<TallySheet> {
  final Map<int, int> _counts = {};

  int get _totalPlates =>
      _counts.values.fold(0, (a, b) => a + b);

  double _outputFor(List<Dish> dishes) {
    double sum = 0;
    _counts.forEach((id, qty) {
      final d = dishes.where((x) => x.id == id).firstOrNull;
      if (d != null && qty > 0) sum += d.price * qty;
    });
    return sum;
  }

  Future<void> _save() async {
    if (_totalPlates == 0) return;
    HapticFeedback.mediumImpact();
    final inv = context.read<InventoryProvider>();
    final txnId = await inv.saveTally(Map.of(_counts));
    if (!mounted) return;
    Navigator.pop(context); // close tally sheet
    if (txnId == null) return;
    showAutoDismissSnackBar(
      ScaffoldMessenger.of(context),
      message:
          '$_totalPlates plates recorded · output today: ${formatCurrency(_outputFor(inv.dishes))}',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          await context
              .read<InventoryProvider>()
              .deleteTapSale(txnId);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    final dishes = [...inv.dishes]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: 16,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const SizedBox(width: 16),
              const Icon(Icons.fact_check_outlined),
              const SizedBox(width: 8),
              const Expanded(
                child: Text("Tally today's sales",
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                  icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                  'Count plates sold today - no need to tap during the rush.',
                  style: TextStyle(fontSize: 13)),
            ),
            const Divider(height: 24),
            Expanded(
              child: dishes.isEmpty
                  ? Center(
                      child: Text('No dishes yet - add one first',
                          style: TextStyle(color: Colors.grey.shade500)))
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final dish in dishes)
                          _TallyRow(
                            dish: dish,
                            count: _counts[dish.id] ?? 0,
                            onChanged: (v) =>
                                setState(() => _counts[dish.id!] = v),
                          ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.teal,
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: _totalPlates > 0 ? _save : null,
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(_totalPlates == 0
                    ? 'Record Sales'
                    : 'Record $_totalPlates plate${_totalPlates == 1 ? '' : 's'}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TallyRow extends StatelessWidget {
  final Dish dish;
  final int count;
  final ValueChanged<int> onChanged;

  const _TallyRow({
    required this.dish,
    required this.count,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dish.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(formatCurrency(dish.price),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: count > 0 ? () => onChanged(count - 1) : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('$count',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => onChanged(count + 1),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      ),
    );
  }
}
