class TransactionItem {
  final int? id;
  final int transactionId;
  final String itemName;
  final int quantity;
  final double price;
  final double subtotal;

  TransactionItem({
    this.id,
    required this.transactionId,
    required this.itemName,
    this.quantity = 1,
    this.price = 0,
    double? subtotal,
  }) : subtotal = subtotal ?? price * quantity;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'transaction_id': transactionId,
      'item_name': itemName,
      'quantity': quantity,
      'price': price,
      'subtotal': subtotal,
    };
  }

  factory TransactionItem.fromMap(Map<String, dynamic> map) {
    return TransactionItem(
      id: map['id'] as int?,
      transactionId: map['transaction_id'] as int,
      itemName: map['item_name'] as String,
      quantity: map['quantity'] as int,
      price: (map['price'] as num).toDouble(),
      subtotal: (map['subtotal'] as num).toDouble(),
    );
  }
}