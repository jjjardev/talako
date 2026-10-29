class Transaction {
  final int? id;
  final int? customerId;
  final String date;
  final int totalAmount;
  final int paidAmount;
  final String status;
  final bool isOwnerConsumption;
  final bool isCashSale;
  final bool transcribedToBook;
  final String? transcribedAt;

  Transaction({
    this.id,
    required this.customerId,
    required this.date,
    this.totalAmount = 0,
    this.paidAmount = 0,
    this.status = 'ACTIVE',
    this.isOwnerConsumption = false,
    this.isCashSale = false,
    this.transcribedToBook = false,
    this.transcribedAt,
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
      'transcribed_to_book': transcribedToBook ? 1 : 0,
      'transcribed_at': transcribedAt,
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
      transcribedToBook: (map['transcribed_to_book'] as num? ?? 0) == 1,
      transcribedAt: map['transcribed_at'] as String?,
    );
  }

  Transaction copyWith({
    int? id,
    int? customerId,
    String? date,
    int? totalAmount,
    int? paidAmount,
    String? status,
    bool? isOwnerConsumption,
    bool? isCashSale,
    bool? transcribedToBook,
    String? transcribedAt,
    bool clearTranscribedAt = false,
  }) {
    return Transaction(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      date: date ?? this.date,
      totalAmount: totalAmount ?? this.totalAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      status: status ?? this.status,
      isOwnerConsumption: isOwnerConsumption ?? this.isOwnerConsumption,
      isCashSale: isCashSale ?? this.isCashSale,
      transcribedToBook: transcribedToBook ?? this.transcribedToBook,
      transcribedAt: clearTranscribedAt
          ? null
          : (transcribedAt ?? this.transcribedAt),
    );
  }
}
