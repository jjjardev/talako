/// Money helpers. All amounts are integer minor units (centavos).
library;

/// Parses a user-entered major-unit string ("12.34") into minor units.
/// Rounds half-up at the third decimal. Returns null when the input is not a
/// plain decimal number.
int? parseMajorToMinor(String input) {
  var text = input.trim().replaceAll(',', '');
  if (text.isEmpty) return null;
  final negative = text.startsWith('-');
  if (negative) text = text.substring(1);
  final parts = text.split('.');
  if (parts.length > 2) return null;
  final whole = parts[0].isEmpty ? '0' : parts[0];
  if (!RegExp(r'^\d+$').hasMatch(whole)) return null;
  final fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.isNotEmpty && !RegExp(r'^\d+$').hasMatch(fraction)) return null;

  final wholeValue = int.tryParse(whole);
  if (wholeValue == null) return null;
  final padded = fraction.padRight(3, '0');
  var minor = wholeValue * 100 + int.parse(padded.substring(0, 2));
  if (padded.length > 2 && int.parse(padded[2]) >= 5) minor++;
  return negative ? -minor : minor;
}

/// Major-unit plain text for editable fields: 1234 -> "12.34".
String formatMinorPlain(int minor) {
  final negative = minor < 0;
  final abs = negative ? -minor : minor;
  final whole = abs ~/ 100;
  final cents = abs % 100;
  final text = cents == 0
      ? whole.toString()
      : '$whole.${cents.toString().padLeft(2, '0')}';
  return negative ? '-$text' : text;
}

/// Legacy double -> minor conversion, only for receiving old JSON backups.
int majorToMinor(num major) => (major * 100).round();

bool isFullPayment(int paid, int total) => paid == total;

int clampMinor(int value, int min, int max) => value.clamp(min, max);
