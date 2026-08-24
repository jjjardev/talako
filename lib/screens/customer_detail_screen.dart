import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/transactions_provider.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import '../utils/pay_flow.dart';

class CustomerDetailScreen extends StatefulWidget {
  final int customerId;
  final String customerName;

  const CustomerDetailScreen({
    super.key,
    required this.customerId,
    required this.customerName,
  });

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  List<ActiveTransaction> _transactions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<bool> _confirmDelete(ActiveTransaction t) async {
    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this receipt?'),
        content: Text(
            '${t.customerName}: ${t.items.map((i) => i.itemName).join(", ")} - '
            'remaining ${t.remaining.toStringAsFixed(0)} pesos will be erased. '
            'This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
    await context.read<TransactionsProvider>().deleteTransaction(t.id);
    await _load();
    return true;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final txns = await context.read<TransactionsProvider>()
        .fetchCustomerTransactions(widget.customerId);
    if (!mounted) {
      return;
    }
    setState(() {
      _transactions = txns;
      _loading = false;
    });
  }

  double get _totalOutstanding {
    double sum = 0;
    for (final t in _transactions) {
      sum += t.remaining;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.customerName), centerTitle: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _transactions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                      const SizedBox(height: 16),
                      Text('${widget.customerName} has no active debts',
                          style: const TextStyle(fontSize: 18, color: Colors.grey)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 80, left: 8, right: 8, top: 8),
                    children: [
                      Card(
                        color: Colors.teal.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Total Outstanding',
                                  style: TextStyle(
                                      fontSize: 16, color: Colors.grey.shade800)),
                              Text(
                                formatCurrency(_totalOutstanding),
                                style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal.shade900),
                              ),
                            ],
                          ),
                        ),
                      ),
                      for (final t in _transactions)
                        Dismissible(
                          key: ValueKey(t.id),
                          direction: DismissDirection.startToEnd,
                          background: Container(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.only(left: 20),
                            color: Colors.red,
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          confirmDismiss: (_) => _confirmDelete(t),
                          onDismissed: (_) {},
                        child: _ReceiptTile(
                          t: t,
                          onChanged: _load,
                          onDelete: _confirmDelete,
                        ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _ReceiptTile extends StatelessWidget {
  final ActiveTransaction t;
  final VoidCallback onChanged;
  final Future<bool> Function(ActiveTransaction) onDelete;

  const _ReceiptTile({
    required this.t,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final txnDate = DateTime.parse(t.date);
    final daysAgo = DateTime.now().difference(txnDate).inDays;
    final cutoff14 = DateTime.now().subtract(const Duration(days: 14));
    final cutoff7 = DateTime.now().subtract(const Duration(days: 7));

    Color bgColor;
    Color textColor;
    String daysLabel;
    final formattedDate = formatDate(t.date);
    if (txnDate.isBefore(cutoff14)) {
      bgColor = Colors.red.shade50;
      textColor = Colors.red.shade800;
      daysLabel = '$daysAgo days ago - $formattedDate (Overdue!)';
    } else if (txnDate.isBefore(cutoff7)) {
      bgColor = Colors.orange.shade50;
      textColor = Colors.orange.shade800;
      daysLabel = '$daysAgo days ago - $formattedDate';
    } else {
      bgColor = Colors.grey.shade50;
      textColor = Colors.grey.shade800;
      daysLabel = daysAgo == 0 ? 'Today - $formattedDate' : '$daysAgo days ago - $formattedDate';
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(daysLabel,
                    style: TextStyle(fontSize: 12, color: textColor.withValues(alpha: 0.6))),
                ),
                SizedBox(
                  height: 28,
                  width: 28,
                  child: IconButton(
                    tooltip: 'Delete receipt',
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    style: IconButton.styleFrom(
                        foregroundColor: Colors.red.shade400),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await onDelete(t);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(2),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                for (final item in t.items)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(item.itemName,
                          style: TextStyle(fontSize: 13, color: textColor)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('${item.quantity} x ${formatCurrency(item.price)}',
                          style: TextStyle(fontSize: 13, color: textColor.withValues(alpha: 0.7)),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(formatCurrency(item.subtotal),
                          style: TextStyle(fontSize: 13, color: textColor, fontWeight: FontWeight.w500),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const Divider(height: 16),
            Row(
              children: [
                Text('Paid: ${formatCurrency(t.paidAmount)} of ${formatCurrency(t.totalAmount)}',
                  style: TextStyle(fontSize: 13, color: textColor.withValues(alpha: 0.7))),
                const Spacer(),
                Text(formatCurrency(t.remaining),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                const SizedBox(width: 8),
                SizedBox(
                  height: 36,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.payments, size: 18),
                    label: const Text('Pay', style: TextStyle(fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: () => openPayFlow(context, t, onAfter: onChanged),
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
