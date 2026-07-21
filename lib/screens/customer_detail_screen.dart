import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';
import '../models/customer.dart';
import '../models/credit_entry.dart';
import '../providers/customers_provider.dart';
import '../widgets/credit_tile.dart';
import '../utils/currency_format.dart';

class CustomerDetailScreen extends StatefulWidget {
  final Customer customer;

  const CustomerDetailScreen({super.key, required this.customer});

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  final _db = DatabaseHelper.instance;
  List<CreditEntry> _credits = [];
  List<CreditEntry> _settledCredits = [];
  bool _showSettled = false;
  bool _loading = true;
  double _outstanding = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final provider = context.read<CustomersProvider>();
    _credits = await provider.getUnsettledCredits(widget.customer.id!);
    _settledCredits = await provider.getSettledCredits(widget.customer.id!);
    _outstanding = await provider.getOutstandingBalance(widget.customer.id!);
    if (mounted) setState(() => _loading = false);
  }

  List<CreditEntry> get _displayCredits => _showSettled ? _settledCredits : _credits;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.customer.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share Summary',
            onPressed: _shareSummary,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Card(
                  margin: const EdgeInsets.all(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Outstanding Balance', style: TextStyle(fontSize: 16)),
                        Text(
                          formatCurrency(_outstanding),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const Text('Show settled'),
                      Switch(
                        value: _showSettled,
                        onChanged: (v) => setState(() => _showSettled = v),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _displayCredits.isEmpty
                      ? Center(child: Text(_showSettled ? 'No settled debts' : 'No active credits'))
                      : ListView.builder(
                          itemCount: _displayCredits.length,
                          itemBuilder: (context, index) {
                            final entry = _displayCredits[index];
                            return CreditTile(
                              entry: entry,
                              onPayFull: () => _payFull(entry),
                              onPayPartial: () => _payPartial(entry),
                            );
                          },
                        ),
                ),
                if (!_showSettled && _outstanding > 0)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.payments),
                        label: Text('Pay All (${formatCurrency(_outstanding)})'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _payAll,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _payFull(CreditEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pay Full'),
        content: Text('Mark ${entry.itemName} (${formatCurrency(entry.total)}) as fully paid?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.updateCreditPaidAmount(entry.id!, entry.total);
      await _load();
    }
  }

  Future<void> _payPartial(CreditEntry entry) async {
    final remaining = entry.remaining;
    final controller = TextEditingController();
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Partial Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Remaining: ${formatCurrency(remaining)}'),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Amount (₱)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final amount = double.tryParse(controller.text);
              if (amount == null || amount <= 0 || amount > remaining) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Invalid amount')),
                );
                return;
              }
              Navigator.pop(ctx, amount);
            },
            child: const Text('Pay'),
          ),
        ],
      ),
    );
    if (result != null) {
      final newPaid = entry.paidAmount + result;
      await _db.updateCreditPaidAmount(entry.id!, newPaid);
      await _load();
    }
  }

  Future<void> _payAll() async {
    final totalRemaining = _credits.fold<double>(0, (sum, e) => sum + e.remaining);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pay All'),
        content: Text('Mark all ${_credits.length} item(s) as fully paid for ${formatCurrency(totalRemaining)}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm All Paid')),
        ],
      ),
    );
    if (confirmed == true) {
      for (final entry in _credits) {
        await _db.updateCreditPaidAmount(entry.id!, entry.total);
      }
      await _load();
    }
  }

  Future<void> _shareSummary() async {
    final lines = <String>[
      'CREDIT SUMMARY - ${widget.customer.name}',
      'Date: ${DateTime.now().toString().substring(0, 10)}',
      '=${'=' * 30}',
    ];
    double grandTotal = 0;
    for (final entry in _credits) {
      lines.add(entry.itemName);
      lines.add('  ${entry.quantity} × ${formatCurrency(entry.pricePerUnit)} = ${formatCurrency(entry.total)}');
      lines.add('  Remaining: ${formatCurrency(entry.remaining)}');
      grandTotal += entry.remaining;
    }
    lines.add('=${'=' * 30}');
    lines.add('TOTAL BALANCE: ${formatCurrency(grandTotal)}');
    await Share.share(lines.join('\n'), subject: 'Credit Summary - ${widget.customer.name}');
  }
}
