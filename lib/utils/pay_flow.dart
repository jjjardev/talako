import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/transactions_provider.dart';
import '../utils/money.dart';
import '../utils/snackbars.dart';
import '../utils/currency_format.dart';
import '../screens/pay_sheet.dart';

Future<void> openPayFlow(
  BuildContext context,
  ActiveTransaction t, {
  VoidCallback? onAfter,
}) async {
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
  if (amount == null) return;
  if (!context.mounted) return;

  final isFull = isFullPayment(amount, t.remaining);
  final messenger = ScaffoldMessenger.of(context);
  final provider = context.read<TransactionsProvider>();
  showAutoDismissSnackBar(
    messenger,
    message: isFull ? 'Payment complete!' : 'Payment of ${formatCurrency(amount)} recorded',
    action: SnackBarAction(
      label: 'Undo',
      onPressed: () {
        messenger.clearSnackBars();
        provider.reversePayment(t.id, amount);
      },
    ),
  );
  await provider.loadActiveTransactions();
  onAfter?.call();
}
