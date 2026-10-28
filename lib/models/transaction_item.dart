class TransactionItem {
  final int? id;
  final int transactionId;
  final int? itemId;
  final String itemName;
  final int quantity;
  final int price;
  final int subtotal;

  TransactionItem({
    this.id,
    required this.transactionId,
    this.itemId,
    required this.itemName,
    this.quantity = 1,
    this.price = 0,
    int? subtotal,
  }) : subtotal = subtotal ?? price * quantity;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'transaction_id': transactionId,
      'item_id': itemId,
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
      itemId: map['item_id'] as int?,
      itemName: map['item_name'] as String,
      quantity: (map['quantity'] as num).toInt(),
      price: (map['price'] as num).toInt(),
      subtotal: (map['subtotal'] as num).toInt(),
    );
  }
}
