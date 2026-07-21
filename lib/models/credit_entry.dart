class CreditEntry {
  final int? id;
  final int customerId;
  final String itemName;
  final int quantity;
  final double pricePerUnit;
  final double total;
  final double paidAmount;
  final String timestamp;

  CreditEntry({
    this.id,
    required this.customerId,
    required this.itemName,
    required this.quantity,
    required this.pricePerUnit,
    required this.total,
    this.paidAmount = 0,
    String? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().toIso8601String();

  double get remaining => total - paidAmount;
  bool get isSettled => paidAmount >= total;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'customer_id': customerId,
      'item_name': itemName,
      'quantity': quantity,
      'price_per_unit': pricePerUnit,
      'total': total,
      'paid_amount': paidAmount,
      'timestamp': timestamp,
    };
  }

  factory CreditEntry.fromMap(Map<String, dynamic> map) {
    return CreditEntry(
      id: map['id'] as int?,
      customerId: map['customer_id'] as int,
      itemName: map['item_name'] as String,
      quantity: map['quantity'] as int,
      pricePerUnit: (map['price_per_unit'] as num).toDouble(),
      total: (map['total'] as num).toDouble(),
      paidAmount: (map['paid_amount'] as num).toDouble(),
      timestamp: map['timestamp'] as String,
    );
  }

  CreditEntry copyWith({
    int? id,
    int? customerId,
    String? itemName,
    int? quantity,
    double? pricePerUnit,
    double? total,
    double? paidAmount,
    String? timestamp,
  }) {
    return CreditEntry(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      itemName: itemName ?? this.itemName,
      quantity: quantity ?? this.quantity,
      pricePerUnit: pricePerUnit ?? this.pricePerUnit,
      total: total ?? this.total,
      paidAmount: paidAmount ?? this.paidAmount,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
