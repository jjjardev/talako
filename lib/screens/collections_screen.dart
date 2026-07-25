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
  String _searchQuery = '';

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
        title: const Text('Credit Book'),
        centerTitle: true,
        actions: [
          Consumer<TransactionsProvider>(
            builder: (context, provider, _) {
              return IconButton(
                icon: Icon(provider.isGrouped ? Icons.list_alt : Icons.merge_type),
                tooltip: provider.isGrouped ? 'Show individual' : 'Group by customer',
                onPressed: () {
                  if (provider.isGrouped) {
                    provider.setGrouped(false);
                  } else {
                    provider.loadGroupedTransactions();
                    provider.setGrouped(true);
                  }
                },
              );
            },
          ),
        ],
      ),
      body: Consumer<TransactionsProvider>(
        builder: (context, provider, _) {
          final hasData = provider.isGrouped
              ? provider.groupedCustomers.isNotEmpty
              : provider.activeTransactions.isNotEmpty;

          if (!hasData) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No active debts', style: TextStyle(fontSize: 18, color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('Tap + to record a credit', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return Column(
            children: [
              _buildSummaryBar(provider),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: provider.isGrouped ? 'Search customers...' : 'Search by name...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80, left: 8, right: 8),
                  itemCount: provider.isGrouped
                      ? _filteredGrouped(provider).length
                      : _filteredIndividual(provider).length,
                  itemBuilder: (context, index) {
                    if (provider.isGrouped) {
                      final g = _filteredGrouped(provider)[index];
                      return _GroupedTile(g: g);
                    } else {
                      final t = _filteredIndividual(provider)[index];
                      return _TransactionTile(t: t);
                    }
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<ActiveTransaction> _filteredIndividual(TransactionsProvider provider) {
    if (_searchQuery.isEmpty) return provider.activeTransactions;
    return provider.activeTransactions.where((t) =>
      t.customerName.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
  }

  List<GroupedCustomer> _filteredGrouped(TransactionsProvider provider) {
    if (_searchQuery.isEmpty) return provider.groupedCustomers;
    return provider.groupedCustomers.where((g) =>
      g.customerName.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
  }

  Widget _buildSummaryBar(TransactionsProvider provider) {
    double overdueTotal = 0;
    double total = 0;

    if (provider.isGrouped) {
      for (final g in provider.groupedCustomers) {
        total += g.remaining;
        final cutoff = DateTime.now().subtract(const Duration(days: 14));
        if (DateTime.parse(g.oldestDate).isBefore(cutoff)) {
          overdueTotal += g.remaining;
        }
      }
    } else {
      overdueTotal = provider.totalOverdue;
      total = provider.totalOutstanding;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (overdueTotal > 0)
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
                        'Overdue: ${formatCurrency(overdueTotal)}',
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

  void _openPay(BuildContext context) async {
    final amount = await showModalBottomSheet<double>(
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
    );
    if (amount != null && context.mounted) {
      final isFull = (amount - t.remaining).abs() < 0.01;
      final messenger = ScaffoldMessenger.of(context);
      final provider = context.read<TransactionsProvider>();
      messenger.showSnackBar(
        SnackBar(
          content: Text(isFull ? 'Payment complete!' : 'Payment of ${formatCurrency(amount)} recorded'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              messenger.clearSnackBars();
              provider.reversePayment(t.id, amount);
            },
          ),
        ),
      );
    }
    if (context.mounted) {
      context.read<TransactionsProvider>().loadActiveTransactions();
    }
  }
}

class _GroupedTile extends StatelessWidget {
  final GroupedCustomer g;

  const _GroupedTile({required this.g});

  @override
  Widget build(BuildContext context) {
    final oldestDate = DateTime.parse(g.oldestDate);
    final cutoff14 = DateTime.now().subtract(const Duration(days: 14));
    final cutoff7 = DateTime.now().subtract(const Duration(days: 7));

    Color bgColor;
    Color textColor;
    if (oldestDate.isBefore(cutoff14)) {
      bgColor = Colors.red.shade50;
      textColor = Colors.red.shade800;
    } else if (oldestDate.isBefore(cutoff7)) {
      bgColor = Colors.orange.shade50;
      textColor = Colors.orange.shade800;
    } else {
      bgColor = Colors.grey.shade50;
      textColor = Colors.grey.shade800;
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
                    g.customerName,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                  ),
                ),
                Text('${g.transactionCount} receipts',
                  style: TextStyle(fontSize: 12, color: textColor.withValues(alpha: 0.6))),
              ],
            ),
            const SizedBox(height: 6),
            Text('Oldest: ${formatDateShort(g.oldestDate)}',
              style: TextStyle(fontSize: 12, color: textColor.withValues(alpha: 0.5))),
            const Divider(height: 16),
            Row(
              children: [
                Text('Paid: ${formatCurrency(g.paidAmount)} of ${formatCurrency(g.totalAmount)}',
                  style: TextStyle(fontSize: 13, color: textColor.withValues(alpha: 0.7))),
                const Spacer(),
                Text(formatCurrency(g.remaining),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
