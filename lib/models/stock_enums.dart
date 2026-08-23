import 'package:flutter/material.dart';

enum UsageType { retailOnly, ingredientOnly, both }

extension UsageTypeX on UsageType {
  String get dbValue => switch (this) {
        UsageType.retailOnly => 'retail_only',
        UsageType.ingredientOnly => 'ingredient_only',
        UsageType.both => 'both',
      };

  String get label => switch (this) {
        UsageType.retailOnly => 'Retail',
        UsageType.ingredientOnly => 'Ingredient',
        UsageType.both => 'Both',
      };

  IconData get icon => switch (this) {
        UsageType.retailOnly => Icons.storefront_outlined,
        UsageType.ingredientOnly => Icons.soup_kitchen_outlined,
        UsageType.both => Icons.restaurant_menu,
      };

  static UsageType fromDb(String? value) =>
      UsageType.values.firstWhere(
        (t) => t.dbValue == value,
        orElse: () => UsageType.retailOnly,
      );
}

enum StockStatus { wellStocked, runningLow, outOfStock, cold }

extension StockStatusX on StockStatus {
  String get dbValue => switch (this) {
        StockStatus.wellStocked => 'well_stocked',
        StockStatus.runningLow => 'running_low',
        StockStatus.outOfStock => 'out_of_stock',
        StockStatus.cold => 'cold',
      };

  String get label => switch (this) {
        StockStatus.wellStocked => 'Well Stocked',
        StockStatus.runningLow => 'Running Low',
        StockStatus.outOfStock => 'Out of Stock',
        StockStatus.cold => 'Cold / Dead',
      };

  Color get color => switch (this) {
        StockStatus.wellStocked => Colors.green,
        StockStatus.runningLow => Colors.orange,
        StockStatus.outOfStock => Colors.red,
        StockStatus.cold => Colors.blueGrey,
      };

  /// Tap-cycle order: destructive "Out of Stock" is reachable but the
  /// loop returns to the healthy state first.
  StockStatus next() => switch (this) {
        StockStatus.wellStocked => StockStatus.runningLow,
        StockStatus.runningLow => StockStatus.outOfStock,
        StockStatus.outOfStock => StockStatus.cold,
        StockStatus.cold => StockStatus.wellStocked,
      };

  static StockStatus fromDb(String? value) => StockStatus.values
      .firstWhere((s) => s.dbValue == value, orElse: () => StockStatus.wellStocked);
}

enum FreshnessStatus { fresh, useSoon, frozen, emptySpoiled }

extension FreshnessStatusX on FreshnessStatus {
  String get dbValue => switch (this) {
        FreshnessStatus.fresh => 'fresh',
        FreshnessStatus.useSoon => 'use_soon',
        FreshnessStatus.frozen => 'frozen',
        FreshnessStatus.emptySpoiled => 'empty_spoiled',
      };

  String get label => switch (this) {
        FreshnessStatus.fresh => 'Fresh',
        FreshnessStatus.useSoon => 'Use Soon',
        FreshnessStatus.frozen => 'Frozen',
        FreshnessStatus.emptySpoiled => 'Empty / Spoiled',
      };

  Color get color => switch (this) {
        FreshnessStatus.fresh => Colors.green,
        FreshnessStatus.useSoon => Colors.orange,
        FreshnessStatus.frozen => Colors.lightBlue,
        FreshnessStatus.emptySpoiled => Colors.red,
      };

  /// Destructive state last in the tap cycle (mis-tap safe).
  FreshnessStatus next() => switch (this) {
        FreshnessStatus.fresh => FreshnessStatus.useSoon,
        FreshnessStatus.useSoon => FreshnessStatus.frozen,
        FreshnessStatus.frozen => FreshnessStatus.emptySpoiled,
        FreshnessStatus.emptySpoiled => FreshnessStatus.fresh,
      };

  bool get usable => this == FreshnessStatus.fresh || this == FreshnessStatus.frozen;

  static FreshnessStatus fromDb(String? value) => FreshnessStatus.values
      .firstWhere((f) => f.dbValue == value, orElse: () => FreshnessStatus.fresh);
}

/// What happens to unsold cooked plates at end of day.
enum LeftoverDisposition {
  reheat,
  ingredients,
  spoiled;

  String get dbValue => name;
}

/// Derived, never stored.
enum DishAvailability { available, limited, unavailable }

DishAvailability deriveDishAvailability(List<FreshnessStatus> ingredientStates) {
  if (ingredientStates.any((s) => s == FreshnessStatus.emptySpoiled)) {
    return DishAvailability.unavailable;
  }
  if (ingredientStates.any((s) => s == FreshnessStatus.useSoon)) {
    return DishAvailability.limited;
  }
  return DishAvailability.available;
}
