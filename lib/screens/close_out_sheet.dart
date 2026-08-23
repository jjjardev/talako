import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/stock_enums.dart';
import '../providers/inventory_provider.dart';

/// Manual "End Day" flow: shows today's per-dish sales and lets the owner
/// log unsold cooked plates with a disposition (reheat / ingredient / waste).
class CloseOutSheet extends StatefulWidget {
  const CloseOutSheet({super.key});

  @override
  State<CloseOutSheet> createState() => _CloseOutSheetState();
}

class _CloseOutSheetState extends State<CloseOutSheet> {
  List<Map<String, dynamic>>? _rows;
  final Map<int, int> _qty = {};
  final Map<int, String> _disposition = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final recap = await context.read<InventoryProvider>().recapForToday();
    if (!mounted) return;
    setState(() => _rows = (recap['rows'] as List).cast<Map<String, dynamic>>());
  }

  Future<void> _save() async {
    final inv = context.read<InventoryProvider>();
    final entries = <({int dishId, int qty, String disposition})>[];
    _qty.forEach((dishId, qty) {
      entries.add((
        dishId: dishId,
        qty: qty,
        disposition:
            _disposition[dishId] ?? LeftoverDisposition.reheat.dbValue,
      ));
    });
    await inv.saveLeftovers(entries);
    await inv.markDayClosed();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Day closed - leftovers recorded')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
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
            Row(
              children: [
                const SizedBox(width: 16),
                const Icon(Icons.nightlight_outlined),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('End Day',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                    icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                  'Any unsold cooked plates? Log them so tomorrow knows.',
                  style: TextStyle(fontSize: 13)),
            ),
            const Divider(height: 24),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final rows = _rows;
    if (rows == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bedtime_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('No dishes sold today.'),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.teal),
              onPressed: _save,
              child: const Text('Close day anyway',
                  style: TextStyle(color: Colors.white)),
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        for (final row in rows)
          _LeftoverRow(
            dishId: row['dish_id'] as int,
            name: row['name'] as String,
            platesSold: row['plates'] as int,
            qty: _qty[row['dish_id']] ?? 0,
            disposition: _disposition[row['dish_id']] ??
                LeftoverDisposition.reheat.dbValue,
            onQty: (q) => setState(() => _qty[row['dish_id'] as int] = q),
            onDisposition: (d) =>
                setState(() => _disposition[row['dish_id'] as int] = d),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.teal),
          onPressed: _save,
          icon: const Icon(Icons.check),
          label: const Text('Close Day'),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _LeftoverRow extends StatelessWidget {
  final int dishId;
  final String name;
  final int platesSold;
  final int qty;
  final String disposition;
  final ValueChanged<int> onQty;
  final ValueChanged<String> onDisposition;

  const _LeftoverRow({
    required this.dishId,
    required this.name,
    required this.platesSold,
    required this.qty,
    required this.disposition,
    required this.onQty,
    required this.onDisposition,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text(name,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
              Text('sold ${platesSold}x',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              const Text('Unsold:',
                  style: TextStyle(fontSize: 13)),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: qty > 0 ? () => onQty(qty - 1) : null,
                icon: const Icon(Icons.remove_circle_outline, size: 20),
              ),
              Text('$qty',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => onQty(qty + 1),
                icon: const Icon(Icons.add_circle_outline, size: 20),
              ),
            ]),
            if (qty > 0)
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'reheat', label: Text('Reheat'), icon: Icon(Icons.microwave_outlined, size: 16)),
                  ButtonSegment(value: 'ingredients', label: Text('Ingredient')),
                  ButtonSegment(value: 'spoiled', label: Text('Waste')),
                ],
                selected: {disposition},
                onSelectionChanged: (s) => onDisposition(s.first),
              ),
          ],
        ),
      ),
    );
  }
}
