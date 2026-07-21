class Item {
  final int? id;
  final String name;
  final double price;
  final String createdAt;

  Item({this.id, required this.name, required this.price, String? createdAt})
      : createdAt = createdAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'price': price,
      'created_at': createdAt,
    };
  }

  factory Item.fromMap(Map<String, dynamic> map) {
    return Item(
      id: map['id'] as int?,
      name: map['name'] as String,
      price: (map['price'] as num).toDouble(),
      createdAt: map['created_at'] as String,
    );
  }

  Item copyWith({
    int? id,
    String? name,
    double? price,
    String? createdAt,
  }) {
    return Item(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
