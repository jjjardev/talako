import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/transactions_provider.dart';
import '../utils/currency_format.dart';
import 'bayad_sheet.dart';

class PangolektaScreen extends StatefulWidget {
  const PangolektaScreen({super.key});

  @override
  State<PangolektaScreen> createState() => _PangolektaScreenState();
}

class _PangolektaScreenState extends State<PangolektaScreen> {
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
        title: const Text('Pangolekta'),
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
                  Text('No active utang', style: TextStyle(fontSize: 18, color: Colors.grey)),
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
                  const Text('Total Utang', style: TextStyle(fontSize: 16)),
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
    if (txnDate.isBefore(cutoff14)) {
      bgColor = Colors.red.shade50;
      textColor = Colors.red.shade800;
      daysLabel = '$daysAgo days (Overdue!)';
    } else if (txnDate.isBefore(cutoff7)) {
      bgColor = Colors.orange.shade50;
      textColor = Colors.orange.shade800;
      daysLabel = '$daysAgo days';
    } else {
      bgColor = Colors.grey.shade50;
      textColor = Colors.grey.shade800;
      daysLabel = daysAgo == 0 ? 'Today' : '$daysAgo days';
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
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.payments, size: 18),
                    label: const Text('Bayad', style: TextStyle(fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: () => _openBayad(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(t.itemsSummary,
              style: TextStyle(fontSize: 13, color: textColor.withValues(alpha: 0.7)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(daysLabel,
                  style: TextStyle(fontSize: 12, color: textColor.withValues(alpha: 0.6))),
                const Spacer(),
                Text(formatCurrency(t.remaining),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openBayad(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => BayadSheet(
        transactionId: t.id,
        customerName: t.customerName,
        remainingBalance: t.remaining,
      ),
    ).then((_) {
      context.read<TransactionsProvider>().loadActiveTransactions();
    });
  }
}