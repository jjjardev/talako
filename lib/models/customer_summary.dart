import 'customer.dart';

class CustomerSummary {
  final Customer customer;
  final double balance;
  final bool hasOverdue;

  CustomerSummary({
    required this.customer,
    required this.balance,
    required this.hasOverdue,
  });
}
