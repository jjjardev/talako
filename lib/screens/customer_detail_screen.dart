import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../providers/customers_provider.dart';
import '../utils/currency_format.dart';
import 'bayad_sheet.dart';

class CustomerDetailScreen extends StatefulWidget {
  final Customer customer;

  const CustomerDetailScreen({super.key, required this.customer});

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  final _db = DatabaseHelper.instance;
  List<Transaction> _activeTransactions = [];
  List<Transaction> _paidTransactions = [];
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
    _activeTransactions = await provider.getActiveTransactions(widget.customer.id!);
    _paidTransactions = await provider.getPaidTransactions(widget.customer.id!);
    _outstanding = await provider.getOutstandingBalance(widget.customer.id!);
    if (mounted) setState(() => _loading = false);
  }

  List<Transaction> get _display => _showSettled ? _paidTransactions : _activeTransactions;

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
                      const Text('Show paid'),
                      Switch(
                        value: _showSettled,
                        onChanged: (v) => setState(() => _showSettled = v),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _display.isEmpty
                      ? Center(child: Text(_showSettled ? 'No paid transactions' : 'No active utang'))
                      : ListView.builder(
                          itemCount: _display.length,
                          itemBuilder: (context, index) {
                            final txn = _display[index];
                            return _TransactionCard(
                              transaction: txn,
                              showBayad: !_showSettled,
                              onBayad: () => _openBayad(context, txn),
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

  void _openBayad(BuildContext context, Transaction txn) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => BayadSheet(
        transactionId: txn.id!,
        customerName: widget.customer.name,
        remainingBalance: txn.remaining,
      ),
    ).then((_) => _load());
  }

  Future<void> _payAll() async {
    final totalRemaining = _activeTransactions.fold<double>(0, (sum, t) => sum + t.remaining);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pay All'),
        content: Text('Pay ALL active transactions (${_activeTransactions.length}) for ${formatCurrency(totalRemaining)}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm All Paid')),
        ],
      ),
    );
    if (confirmed == true) {
      for (final txn in _activeTransactions) {
        await _db.updateTransactionPayment(txn.id!, txn.totalAmount);
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
    for (final txn in _activeTransactions) {
      final items = await _db.getItemsByTransaction(txn.id!);
      final dateStr = txn.date.substring(0, 10);
      lines.add('');
      lines.add('Receipt $dateStr: ${formatCurrency(txn.remaining)} remaining');
      for (final item in items) {
        lines.add('  ${item.quantity}x ${item.itemName} @ ${formatCurrency(item.price)} = ${formatCurrency(item.subtotal)}');
      }
      grandTotal += txn.remaining;
    }
    lines.add('=${'=' * 30}');
    lines.add('TOTAL BALANCE: ${formatCurrency(grandTotal)}');
    await Share.share(lines.join('\n'), subject: 'Credit Summary - ${widget.customer.name}');
  }
}

class _TransactionCard extends StatelessWidget {
  final Transaction transaction;
  final bool showBayad;
  final VoidCallback onBayad;

  const _TransactionCard({
    required this.transaction,
    required this.showBayad,
    required this.onBayad,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = transaction.remaining;
    final dateStr = transaction.date.substring(0, 10);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  transaction.isPaid ? Icons.check_circle : Icons.receipt_long,
                  color: transaction.isPaid ? Colors.green : Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(dateStr, style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                if (transaction.isPaid)
                  const Text('PAID', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Total: ${formatCurrency(transaction.totalAmount)}', style: const TextStyle(fontSize: 14)),
            if (!transaction.isPaid) ...[
              const SizedBox(height: 4),
              Text('Remaining: ${formatCurrency(remaining)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red)),
              if (showBayad)
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.payments, size: 18),
                    label: const Text('Bayad'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    onPressed: onBayad,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}