import 'package:flutter/material.dart';
import '../utils/currency_format.dart';

class CustomerTile extends StatelessWidget {
  final String name;
  final double balance;
  final bool hasOverdue;
  final VoidCallback onTap;

  const CustomerTile({
    super.key,
    required this.name,
    required this.balance,
    required this.hasOverdue,
    required this.onTap,
  });

  static const _overdueColor = Color(0x1AF44336);

  @override
  Widget build(BuildContext context) {
    return Card(
      color: hasOverdue ? _overdueColor : null,
      child: ListTile(
        leading: hasOverdue
            ? const Icon(Icons.warning_amber, color: Colors.orange)
            : const Icon(Icons.person_outline),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(formatCurrency(balance)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
