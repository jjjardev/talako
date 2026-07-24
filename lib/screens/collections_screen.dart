import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/transactions_provider.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import 'pay_sheet.dart';

class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TransactionsProvider>().loadActiveTransactions();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Collections'),
        centerTitle: true,
      ),
      body: Consumer<TransactionsProvider>(
        builder: (context, provider, _) {
          if (provider.activeTransactions.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No active debts', style: TextStyle(fontSize: 18, color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('Tap + to add a new credit', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          return Column(
            children: [
              _buildSummaryBar(provider),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: provider.activeTransactions.length,
                  itemBuilder: (context, index) {
                    final t = provider.activeTransactions[index];
                    return _TransactionTile(t: t);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryBar(TransactionsProvider provider) {
    final overdue = provider.totalOverdue;
    final total = provider.totalOutstanding;
    return Container(
      padding: const EdgeInsets.all(12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (overdue > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Overdue: ${formatCurrency(overdue)}',
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Outstanding', style: TextStyle(fontSize: 16)),
                  Text(
                    formatCurrency(total),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final ActiveTransaction t;

  const _TransactionTile({required this.t});

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
                  child: Text(
                    t.customerName,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                  ),
                ),
                Text(daysLabel,
                  style: TextStyle(fontSize: 12, color: textColor.withValues(alpha: 0.6))),
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
                Text('Total: ${formatCurrency(t.totalAmount)}',
                  style: TextStyle(fontSize: 13, color: textColor.withValues(alpha: 0.7))),
                if (t.paidAmount > 0) ...[
                  const SizedBox(width: 8),
                  Text('Paid: ${formatCurrency(t.paidAmount)}',
                    style: TextStyle(fontSize: 13, color: textColor.withValues(alpha: 0.7))),
                ],
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
                    onPressed: () => _openPay(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openPay(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PaySheet(
        transactionId: t.id,
        customerName: t.customerName,
        remainingBalance: t.remaining,
      ),
    ).then((_) {
      context.read<TransactionsProvider>().loadActiveTransactions();
    });
  }
}