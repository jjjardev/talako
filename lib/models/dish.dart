import '../utils/money.dart';

class Dish {
  final int? id;
  final String name;
  final double price;
  final double capital;
  final String createdAt;

  Dish({
    this.id,
    required this.name,
    required this.price,
    this.capital = 0,
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  /// Per-plate earnings: price per serving minus cost per plate.
  double get margin => roundMoney(price - capital);

  /// Margin as a fraction of price (0.0 when price is 0).
  double get marginRate => price <= 0 ? 0 : margin / price;

  /// Fraction of the whole-dish capital earned back, given all-time
  /// [revenue] for this dish. 1.0 = puhunan fully recovered.
  double recoveryRate(double revenue) =>
      capital <= 0 ? 1.0 : (revenue / capital).clamp(0.0, 1.0);

  bool get thinMargin => price > 0 && capital > 0 && marginRate < 0.20;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'price': price,
        'capital': capital,
        'created_at': createdAt,
      };

  factory Dish.fromMap(Map<String, dynamic> map) => Dish(
        id: map['id'] as int?,
        name: map['name'] as String,
        price: (map['price'] as num).toDouble(),
        capital: (map['capital'] as num?)?.toDouble() ?? 0,
        createdAt: map['created_at'] as String,
      );

  Dish copyWith({int? id, String? name, double? price, double? capital}) =>
      Dish(
        id: id ?? this.id,
        name: name ?? this.name,
        price: price ?? this.price,
        capital: capital ?? this.capital,
        createdAt: createdAt,
      );
}

class SpoilageEntry {
  final int? id;
  final int itemId;
  final String itemName;
  final double estimatedValue;
  final String? note;
  final String date;

  SpoilageEntry({
    this.id,
    required this.itemId,
    this.itemName = '',
    required this.estimatedValue,
    this.note,
    required this.date,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'item_id': itemId,
        'estimated_value': estimatedValue,
        'note': note,
        'date': date,
      };

  factory SpoilageEntry.fromMap(Map<String, dynamic> map) => SpoilageEntry(
        id: map['id'] as int?,
        itemId: map['item_id'] as int,
        itemName: (map['item_name'] as String?) ?? '',
        estimatedValue: (map['estimated_value'] as num).toDouble(),
        note: map['note'] as String?,
        date: map['date'] as String,
      );
}
