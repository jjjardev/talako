import 'item.dart';
import 'stock_enums.dart';

class Dish {
  final int? id;
  final String name;
  final double price;
  final String createdAt;

  Dish({
    this.id,
    required this.name,
    required this.price,
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'price': price,
        'created_at': createdAt,
      };

  factory Dish.fromMap(Map<String, dynamic> map) => Dish(
        id: map['id'] as int?,
        name: map['name'] as String,
        price: (map['price'] as num).toDouble(),
        createdAt: map['created_at'] as String,
      );

  Dish copyWith({int? id, String? name, double? price}) => Dish(
        id: id ?? this.id,
        name: name ?? this.name,
        price: price ?? this.price,
        createdAt: createdAt,
      );
}

class DishIngredientLine {
  final int itemId;
  final String itemName;
  final FreshnessStatus freshness;
  final bool isIngredient;

  DishIngredientLine({
    required this.itemId,
    required this.itemName,
    required this.freshness,
    this.isIngredient = true,
  });

  factory DishIngredientLine.fromItem(Item item) => DishIngredientLine(
        itemId: item.id!,
        itemName: item.name,
        freshness: item.freshnessStatus,
        isIngredient: item.isIngredient,
      );
}

class DishWithIngredients {
  final Dish dish;
  final List<DishIngredientLine> ingredients;

  DishWithIngredients({required this.dish, this.ingredients = const []});

  /// A dish with no defined ingredients is incomplete, never "available".
  DishAvailability get availability {
    if (ingredients.isEmpty) return DishAvailability.unavailable;
    return deriveDishAvailability(ingredients.map((i) => i.freshness).toList());
  }

  int get usedInCount => 0; // placeholder for future weekly counts
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
