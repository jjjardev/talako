import 'stock_enums.dart';

class Item {
  final int? id;
  final String name;
  final int price;
  final String createdAt;
  final UsageType usageType;
  final StockStatus stockStatus;
  final String? notes;
  final String? lastStatusUpdated;
  final String? lastRestocked;

  Item({
    this.id,
    required this.name,
    required this.price,
    String? createdAt,
    this.usageType = UsageType.retailOnly,
    this.stockStatus = StockStatus.wellStocked,
    this.notes,
    this.lastStatusUpdated,
    this.lastRestocked,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  bool get isIngredient =>
      usageType == UsageType.ingredientOnly || usageType == UsageType.both;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'price': price,
      'created_at': createdAt,
      'usage_type': usageType.dbValue,
      'stock_status': stockStatus.dbValue,
      'notes': notes,
      'last_status_updated': lastStatusUpdated,
      'last_restocked': lastRestocked,
    };
  }

  factory Item.fromMap(Map<String, dynamic> map) {
    return Item(
      id: map['id'] as int?,
      name: map['name'] as String,
      price: (map['price'] as num).toInt(),
      createdAt: map['created_at'] as String?,
      usageType: UsageTypeX.fromDb(map['usage_type'] as String?),
      stockStatus: StockStatusX.fromDb(map['stock_status'] as String?),
      notes: map['notes'] as String?,
      lastStatusUpdated: map['last_status_updated'] as String?,
      lastRestocked: map['last_restocked'] as String?,
    );
  }

  Item copyWith({
    int? id,
    String? name,
    int? price,
    String? createdAt,
    UsageType? usageType,
    StockStatus? stockStatus,
    String? notes,
    bool clearNotes = false,
    String? lastStatusUpdated,
    String? lastRestocked,
  }) {
    return Item(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      createdAt: createdAt ?? this.createdAt,
      usageType: usageType ?? this.usageType,
      stockStatus: stockStatus ?? this.stockStatus,
      notes: clearNotes ? null : (notes ?? this.notes),
      lastStatusUpdated: lastStatusUpdated ?? this.lastStatusUpdated,
      lastRestocked: lastRestocked ?? this.lastRestocked,
    );
  }
}
