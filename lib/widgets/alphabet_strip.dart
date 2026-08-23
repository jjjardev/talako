import 'package:flutter/material.dart';

/// Contacts-style A-Z index strip. Renders only the letters that exist.
///
/// Deliberately tap-per-letter (onTapDown for instant response): a
/// drag-along-the-strip implementation loses the gesture arena to the
/// scroll views underneath and feels dead on real devices.
class AlphabetStrip extends StatelessWidget {
  final List<String> letters;
  final ValueChanged<String> onLetter;

  const AlphabetStrip({
    super.key,
    required this.letters,
    required this.onLetter,
  });

  /// First letter of a name for indexing ('#' for non-A-Z).
  static String letterFor(String name) {
    final c = name.trim().isEmpty ? '#' : name.trim()[0].toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(c) ? c : '#';
  }

  /// Maps each present letter to the index of its first item (names must be
  /// sorted in the same order the list/grid displays them).
  static Map<String, int> letterOffsets(List<String> names) {
    final map = <String, int>{};
    for (int i = 0; i < names.length; i++) {
      map.putIfAbsent(letterFor(names[i]), () => i);
    }
    final sorted = map.keys.toList()..sort();
    return {for (final l in sorted) l: map[l]!};
  }

  /// Pixel offset that puts the row containing [itemIndex] at the top of a
  /// SliverGridDelegateWithMaxCrossAxisExtent grid. Must mirror the exact
  /// padding/spacing values used by the grid.
  static double gridScrollOffsetFor({
    required int itemIndex,
    required double availableWidth,
    required double horizontalPadding,
    required double maxCrossAxisExtent,
    required double crossAxisSpacing,
    required double mainAxisSpacing,
    required double childAspectRatio,
    double leadingVerticalInset = 0,
  }) {
    final inner =
        (availableWidth - horizontalPadding).clamp(1.0, double.infinity);
    final columns = (inner / maxCrossAxisExtent).floor().clamp(1, 100);
    final cardWidth = inner / columns;
    final cardHeight = cardWidth / childAspectRatio;
    final row = itemIndex ~/ columns;
    // leadingVerticalInset = the grid's top padding (content starts there).
    return leadingVerticalInset + row * (cardHeight + mainAxisSpacing);
  }

  @override
  Widget build(BuildContext context) {
    if (letters.length < 2) return const SizedBox.shrink();
    return Container(
      width: 24,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final l in letters)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) => onLetter(l),
                child: Center(
                  child: Text(
                    l,
                    style: TextStyle(
                      fontSize: _fontSize(l),
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _fontSize(String l) => l.length > 1 ? 9 : 11;
}
