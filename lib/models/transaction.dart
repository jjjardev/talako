class Transaction {
  final int? id;
  final int? customerId;
  final String date;
  final int totalAmount;
  final int paidAmount;
  final String status;
  final bool isOwnerConsumption;
  final bool isCashSale;

  Transaction({
    this.id,
    required this.customerId,
    required this.date,
    this.totalAmount = 0,
    this.paidAmount = 0,
    this.status = 'ACTIVE',
    this.isOwnerConsumption = false,
    this.isCashSale = false,
  });

  int get remaining => totalAmount - paidAmount;
  bool get isPaid => paidAmount >= totalAmount;

  String get derivedStatus => isPaid ? 'PAID' : 'ACTIVE';

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'customer_id': customerId,
      'date': date,
      'total_amount': totalAmount,
      'paid_amount': paidAmount,
      'status': derivedStatus,
      'is_owner_consumption': isOwnerConsumption ? 1 : 0,
      'is_cash_sale': isCashSale ? 1 : 0,
    };
  }

  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'] as int?,
      customerId: map['customer_id'] as int?,
      date: map['date'] as String,
      totalAmount: (map['total_amount'] as num).toInt(),
      paidAmount: (map['paid_amount'] as num).toInt(),
      status: map['status'] as String? ?? 'ACTIVE',
      isOwnerConsumption: (map['is_owner_consumption'] as num? ?? 0) == 1,
      isCashSale: (map['is_cash_sale'] as num? ?? 0) == 1,
    );
  }
}
