class Transaction {
  final int? id;
  final int customerId;
  final String date;
  final double totalAmount;
  final double paidAmount;
  final String status;

  Transaction({
    this.id,
    required this.customerId,
    required this.date,
    this.totalAmount = 0,
    this.paidAmount = 0,
    this.status = 'ACTIVE',
  });

  double get remaining => totalAmount - paidAmount;
  bool get isPaid => status == 'PAID' || paidAmount >= totalAmount;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'customer_id': customerId,
      'date': date,
      'total_amount': totalAmount,
      'paid_amount': paidAmount,
      'status': isPaid ? 'PAID' : 'ACTIVE',
    };
  }

  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'] as int?,
      customerId: map['customer_id'] as int,
      date: map['date'] as String,
      totalAmount: (map['total_amount'] as num).toDouble(),
      paidAmount: (map['paid_amount'] as num).toDouble(),
      status: map['status'] as String? ?? 'ACTIVE',
    );
  }
}