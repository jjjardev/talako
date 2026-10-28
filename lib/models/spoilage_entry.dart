class SpoilageEntry {
  final int? id;
  final int? itemId;
  final String itemName;
  final int estimatedValue;
  final String? note;
  final String date;

  SpoilageEntry({
    this.id,
    this.itemId,
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
        itemId: map['item_id'] as int?,
        itemName: (map['item_name'] as String?) ?? '',
        estimatedValue: (map['estimated_value'] as num).toInt(),
        note: map['note'] as String?,
        date: map['date'] as String,
      );
}
