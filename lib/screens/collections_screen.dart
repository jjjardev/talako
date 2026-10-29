import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/transactions_provider.dart';
import '../providers/customers_provider.dart';
import '../providers/inventory_provider.dart';
import '../utils/backup_service.dart';
import '../utils/currency_format.dart';
import '../utils/date_format.dart';
import '../utils/pay_flow.dart';
import '../utils/snackbars.dart';
import 'add_credit_sheet.dart';
import 'customer_detail_screen.dart';
import 'edit_transaction_sheet.dart';
import '../widgets/alphabet_strip.dart';

class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  String _searchQuery = '';
  final ScrollController _scroll = ScrollController();
  bool _alphaSort = false;
  final Map<int, GlobalKey> _groupKeys = {};

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

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
              if (provider.filter == CreditBookFilter.transcribed) {
                return const SizedBox.shrink();
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (provider.isGrouped)
                    IconButton(
                      icon: Icon(_alphaSort
                          ? Icons.sort_by_alpha
                          : Icons.sort),
                      tooltip: _alphaSort
                          ? 'Sorted by customer name'
                          : 'Sorted oldest first',
                      onPressed: () =>
                          setState(() => _alphaSort = !_alphaSort),
                    ),
                  IconButton(
                    icon: Icon(provider.isGrouped
                        ? Icons.list_alt
                        : Icons.merge_type),
                    tooltip: provider.isGrouped
                        ? 'Show individual'
                        : 'Group by customer',
                    onPressed: () {
                      if (provider.isGrouped) {
                        provider.setGrouped(false);
                      } else {
                        provider.loadGroupedTransactions();
                        provider.setGrouped(true);
                      }
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Consumer<TransactionsProvider>(
        builder: (context, provider, _) {
          return Column(
            children: [
              _filterRow(provider),
              Expanded(child: _buildBody(context, provider)),
            ],
          );
        },
      ),
    );
  }

  Widget _filterRow(TransactionsProvider provider) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          for (final filter in CreditBookFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(filter == CreditBookFilter.transcribed &&
                        provider.transcribedCount > 0
                    ? '${filter.label} (${provider.transcribedCount})'
                    : filter.label),
                selected: provider.filter == filter,
                onSelected: (_) => provider.setFilter(filter),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, TransactionsProvider provider) {
    final grouped =
        provider.isGrouped && provider.filter != CreditBookFilter.transcribed;
    final hasData = switch (provider.filter) {
      CreditBookFilter.transcribed =>
        _filteredTranscribed(provider).isNotEmpty,
      CreditBookFilter.allOpen || CreditBookFilter.active =>
        grouped ? _filteredGrouped(provider).isNotEmpty : _filteredIndividual(provider).isNotEmpty,
    };

    if (!hasData) {
      return Column(
        children: [
          _buildSummaryBar(provider),
          Expanded(child: _buildEmpty(context, provider)),
        ],
      );
    }

    return Column(
      children: [
        _buildSummaryBar(provider),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: TextField(
            decoration: InputDecoration(
              hintText: grouped || provider.filter == CreditBookFilter.transcribed
                  ? 'Search customers...'
                  : 'Search by name...',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => provider.loadActiveTransactions(),
            child: provider.filter == CreditBookFilter.transcribed
                ? _buildTranscribedList(provider)
                : grouped
                    ? _buildGroupedList(provider)
                    : _buildIndividualList(provider),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context, TransactionsProvider provider) {
    final transcribed = provider.transcribedCount;
    final isTranscribed = provider.filter == CreditBookFilter.transcribed;
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
                isTranscribed
                    ? Icons.menu_book_outlined
                    : Icons.receipt_long_outlined,
                size: 64,
                color: Colors.grey),
            const SizedBox(height: 16),
            Text(
                isTranscribed
                    ? 'No transcribed entries yet'
                    : 'No active debts',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, color: Colors.grey)),
            const SizedBox(height: 12),
            if (isTranscribed)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                onPressed: () => provider.setFilter(CreditBookFilter.active),
                icon: const Icon(Icons.receipt_long, size: 18),
                label: const Text('View active credits'),
              )
            else ...[
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                onPressed: () => _openAddCredit(context),
                icon: const Icon(Icons.add),
                label: const Text('Record a credit'),
              ),
              if (provider.filter == CreditBookFilter.active &&
                  transcribed > 0) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () =>
                      provider.setFilter(CreditBookFilter.transcribed),
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: Text('View transcribed ($transcribed)'),
                ),
              ],
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _restoreBackup(context, provider),
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('Restore a backup'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIndividualList(TransactionsProvider provider) {
    final items = _filteredIndividual(provider);
    return ListView.builder(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 80, left: 8, right: 8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final t = items[index];
        return Dismissible(
          key: ValueKey(t.id),
          direction: DismissDirection.startToEnd,
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 20),
            color: Colors.green.shade600,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.payments, color: Colors.white),
                SizedBox(height: 2),
                Text('Fully paid',
                    style: TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          ),
          confirmDismiss: (_) async {
            final amountPaid = t.remaining;
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('Mark ${t.customerName} fully paid?'),
                content: Text('Remaining ${formatCurrency(amountPaid)} '
                    'will be settled.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Yes, fully paid'),
                  ),
                ],
              ),
            );
            if (ok != true) return false;
            await provider.processPayment(t.id, amountPaid);
            if (!context.mounted) return false;
            showAutoDismissSnackBar(
              ScaffoldMessenger.of(context),
              message:
                  '${t.customerName} fully paid · ${formatCurrency(amountPaid)}',
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () => provider.reversePayment(t.id, amountPaid),
              ),
            );
            return false;
          },
          child: _TransactionTile(
            t: t,
            showBadge: provider.filter == CreditBookFilter.allOpen,
            onLongPress: () => _showTransactionActions(context, t),
            onOpenCustomer: () => _openCustomerDetail(
                context,
                GroupedCustomer(
                  customerId: t.customerId,
                  customerName: t.customerName,
                  totalAmount: 0,
                  paidAmount: 0,
                  transactionCount: 0,
                  oldestDate: t.date,
                  latestDate: t.date,
                )),
          ),
        );
      },
    );
  }

  Widget _buildTranscribedList(TransactionsProvider provider) {
    final items = _filteredTranscribed(provider);
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 80, left: 8, right: 8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final t = items[index];
        return _TranscribedTile(
          t: t,
          onLongPress: () => _showTransactionActions(context, t),
          onPay: t.isPaid
              ? null
              : () => openPayFlow(context, t, onAfter: provider.loadActiveTransactions),
          onOpenCustomer: () {
            if (t.customerName.isEmpty) return;
            _openCustomerDetail(
                context,
                GroupedCustomer(
                  customerId: t.customerId,
                  customerName: t.customerName,
                  totalAmount: 0,
                  paidAmount: 0,
                  transactionCount: 0,
                  oldestDate: t.date,
                  latestDate: t.date,
                ));
          },
        );
      },
    );
  }

  Widget _buildGroupedList(TransactionsProvider provider) {
    final groups = _filteredGrouped(provider);
    final sorted = _alphaSort
        ? ([...groups]
          ..sort((a, b) =>
              a.customerName.toLowerCase().compareTo(b.customerName.toLowerCase())))
        : groups;
    final list = ListView.builder(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 80, left: 8, right: 28),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final g = sorted[index];
        final key = _groupKeys.putIfAbsent(g.customerId, () => GlobalKey());
        return _GroupedTile(
          key: key,
          g: g,
          onOpen: () => _openCustomerDetail(context, g),
        );
      },
    );
    if (!_alphaSort) return list;
    return Stack(
      children: [
        list,
        Positioned(
          right: 2,
          top: 0,
          bottom: 0,
          child: Center(
            child: AlphabetStrip(
              letters: AlphabetStrip.letterOffsets(
                sorted.map((g) => g.customerName).toList(),
              ).keys.toList(),
              onLetter: (letter) {
                final match = sorted.firstWhere(
                  (g) => AlphabetStrip.letterFor(g.customerName) == letter,
                  orElse: () => sorted.first,
                );
                final target = _groupKeys[match.customerId]?.currentContext;
                if (target != null) {
                  Scrollable.ensureVisible(target,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openAddCredit(BuildContext context) async {
    final provider = context.read<TransactionsProvider>();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const AddCreditSheet(),
    );
    if (context.mounted) await provider.loadActiveTransactions();
  }

  Future<void> _showTransactionActions(
      BuildContext context, ActiveTransaction t) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(t.transcribedToBook
                  ? Icons.menu_book
                  : Icons.menu_book_outlined,
                  color: Colors.teal),
              title: Text(t.transcribedToBook
                  ? 'Untranscribe'
                  : 'Mark transcribed to book'),
              onTap: () => Navigator.pop(ctx, 'toggle'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit receipt'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    final provider = context.read<TransactionsProvider>();
    if (action == 'edit') {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => EditTransactionSheet(transaction: t),
      );
      return;
    }
    final wasTranscribed = t.transcribedToBook;
    if (wasTranscribed) {
      await provider.unmarkTranscribed(t.id);
    } else {
      await provider.markTranscribed(t.id);
    }
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    showAutoDismissSnackBar(
      messenger,
      message: wasTranscribed
          ? 'Removed transcription mark'
          : 'Marked transcribed to book',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          messenger.clearSnackBars();
          if (wasTranscribed) {
            provider.markTranscribed(t.id);
          } else {
            provider.unmarkTranscribed(t.id);
          }
        },
      ),
    );
  }

  Future<void> _restoreBackup(
      BuildContext context, TransactionsProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore a backup?'),
        content: const Text('This will replace all current data.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final error = await BackupService.pickAndImportJson();
    if (!context.mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    context.read<CustomersProvider>().loadCustomers();
    context.read<InventoryProvider>().loadInventory();
    await provider.loadActiveTransactions();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup restored successfully')));
    }
  }

  List<ActiveTransaction> _filteredIndividual(TransactionsProvider provider) {
    if (_searchQuery.isEmpty) return provider.activeTransactions;
    return provider.activeTransactions.where((t) =>
      t.customerName.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
  }

  List<ActiveTransaction> _filteredTranscribed(
      TransactionsProvider provider) {
    if (_searchQuery.isEmpty) return provider.transcribedTransactions;
    return provider.transcribedTransactions
        .where((t) =>
            t.customerName.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  List<GroupedCustomer> _filteredGrouped(TransactionsProvider provider) {
    if (_searchQuery.isEmpty) return provider.groupedCustomers;
    return provider.groupedCustomers.where((g) =>
      g.customerName.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
  }

  void _openCustomerDetail(BuildContext context, GroupedCustomer g) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerDetailScreen(customerId: g.customerId, customerName: g.customerName),
      ),
    );
    if (context.mounted) {
      context.read<TransactionsProvider>().loadActiveTransactions();
    }
  }

  Widget _buildSummaryBar(TransactionsProvider provider) {
    final overdueTotal = provider.totalOverdueAll;
    final total = provider.totalOutstandingAll;

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
                      Expanded(
                        child: Text(
                          'Overdue: ${formatCurrency(overdueTotal)}'
                          '${provider.overdueCountAll > 0 ? ' · ${provider.overdueCountAll} receipt(s)' : ''}',
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
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
  final VoidCallback? onOpenCustomer;
  final VoidCallback? onLongPress;
  final bool showBadge;

  const _TransactionTile({
    required this.t,
    this.onOpenCustomer,
    this.onLongPress,
    this.showBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final txnDate = DateTime.parse(t.date);
    final daysAgo = DateTime.now().difference(txnDate).inDays;
    final cutoff14 = DateTime.now().subtract(const Duration(days: 14));
    final cutoff7 = DateTime.now().subtract(const Duration(days: 7));

    Color bgColor;
    Color textColor;
    Color moneyColor;
    String daysLabel;
    final formattedDate = formatDate(t.date);
    if (txnDate.isBefore(cutoff14)) {
      bgColor = Colors.red.shade50;
      textColor = Colors.red.shade800;
      moneyColor = Colors.red.shade900;
      daysLabel = '$daysAgo days ago - $formattedDate (Overdue!)';
    } else if (txnDate.isBefore(cutoff7)) {
      bgColor = Colors.orange.shade50;
      textColor = Colors.orange.shade800;
      moneyColor = Colors.orange.shade900;
      daysLabel = '$daysAgo days ago - $formattedDate';
    } else {
      bgColor = Colors.grey.shade50;
      textColor = Colors.grey.shade800;
      moneyColor = Colors.grey.shade900;
      daysLabel = daysAgo == 0 ? 'Today - $formattedDate' : '$daysAgo days ago - $formattedDate';
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: bgColor,
      child: InkWell(
        onLongPress: onLongPress,
        child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onOpenCustomer,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            t.customerName,
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                          ),
                        ),
                        if (onOpenCustomer != null)
                          Icon(Icons.chevron_right, size: 18, color: textColor.withValues(alpha: 0.6)),
                        if (showBadge && t.transcribedToBook) ...[
                          const SizedBox(width: 4),
                          const Tooltip(
                            message: 'In physical book',
                            child: Icon(Icons.menu_book,
                                size: 16, color: Colors.teal),
                          ),
                        ],
                      ],
                    ),
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
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: moneyColor)),
                const Spacer(),
                Text(formatCurrency(t.remaining),
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: moneyColor)),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.payments, size: 18),
                    label: const Text('Pay', style: TextStyle(fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: () => openPayFlow(context, t),
                  ),
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

class _TranscribedTile extends StatelessWidget {
  final ActiveTransaction t;
  final VoidCallback onLongPress;
  final VoidCallback onOpenCustomer;
  final VoidCallback? onPay;

  const _TranscribedTile({
    required this.t,
    required this.onLongPress,
    required this.onOpenCustomer,
    this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final name = t.customerName.isEmpty ? '—' : t.customerName;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onLongPress: onLongPress,
        onTap: onOpenCustomer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.menu_book, size: 20, color: Colors.teal),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      'Transcribed ${t.transcribedAt == null ? '' : formatDateShort(t.transcribedAt!)}',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              if (t.isPaid)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('Paid',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800)),
                )
              else ...[
                Text(formatCurrency(t.remaining),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.payments, size: 18),
                    label: const Text('Pay', style: TextStyle(fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: onPay,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupedTile extends StatelessWidget {
  final GroupedCustomer g;
  final VoidCallback onOpen;

  const _GroupedTile({super.key, required this.g, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final oldestDate = DateTime.parse(g.oldestDate);
    final cutoff14 = DateTime.now().subtract(const Duration(days: 14));
    final cutoff7 = DateTime.now().subtract(const Duration(days: 7));

    Color bgColor;
    Color textColor;
    Color moneyColor;
    if (oldestDate.isBefore(cutoff14)) {
      bgColor = Colors.red.shade50;
      textColor = Colors.red.shade800;
      moneyColor = Colors.red.shade900;
    } else if (oldestDate.isBefore(cutoff7)) {
      bgColor = Colors.orange.shade50;
      textColor = Colors.orange.shade800;
      moneyColor = Colors.orange.shade900;
    } else {
      bgColor = Colors.grey.shade50;
      textColor = Colors.grey.shade800;
      moneyColor = Colors.grey.shade900;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: bgColor,
      child: InkWell(
        onTap: onOpen,
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
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor.withValues(alpha: 0.85))),
                ],
              ),
              const SizedBox(height: 6),
              Text('Oldest: ${formatDateShort(g.oldestDate)}',
                style: TextStyle(fontSize: 13, color: textColor.withValues(alpha: 0.8))),
              const Divider(height: 16),
              Row(
                children: [
                  Text('Paid: ${formatCurrency(g.paidAmount)} of ${formatCurrency(g.totalAmount)}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: moneyColor)),
                  const Spacer(),
                  Text(formatCurrency(g.remaining),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: moneyColor)),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, color: moneyColor),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
