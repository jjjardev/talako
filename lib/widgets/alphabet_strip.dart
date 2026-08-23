import 'package:flutter/material.dart';

/// Contacts-style A-Z index strip. Renders only the letters that exist.
///
/// Uses raw [Listener] pointer events on purpose: a normal vertical-drag
/// GestureDetector loses the gesture arena to ancestor scrollers /
/// RefreshIndicators, which made this strip feel dead. Pointer events
/// always arrive regardless of the arena.
class AlphabetStrip extends StatefulWidget {
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
    return leadingVerticalInset +
        row * (cardHeight + mainAxisSpacing) -
        crossAxisSpacing.clamp(0.0, crossAxisSpacing);
  }

  @override
  State<AlphabetStrip> createState() => _AlphabetStripState();
}

class _AlphabetStripState extends State<AlphabetStrip> {
  String? _active;

  void _handle(Offset local) {
    final box = context.findRenderObject() as RenderBox?;
    final height = box?.size.height ?? 0;
    if (widget.letters.isEmpty || height <= 0) return;
    final slot = (local.dy / height * widget.letters.length).floor();
    final i = slot.clamp(0, widget.letters.length - 1);
    widget.onLetter(widget.letters[i]);
    if (_active != widget.letters[i]) {
      setState(() => _active = widget.letters[i]);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.letters.length < 2) return const SizedBox.shrink();
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (d) => _handle(d.localPosition),
      onPointerMove: (d) => _handle(d.localPosition),
      onPointerUp: (_) => setState(() => _active = null),
      onPointerCancel: (_) => setState(() => _active = null),
      child: Container(
        width: 22,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final l in widget.letters)
              Expanded(
                child: Center(
                  child: Text(
                    l,
                    style: TextStyle(
                      fontSize: _active == l ? 13 : 10,
                      fontWeight:
                          _active == l ? FontWeight.bold : FontWeight.w500,
                      color: _active == l
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade500,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
