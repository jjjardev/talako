import 'package:flutter_test/flutter_test.dart';
import 'package:talako/utils/currency_format.dart';
import 'package:talako/utils/date_format.dart';

void main() {
  test('formatCurrency uses peso symbol and groups thousands', () {
    final out = formatCurrency(123450);
    expect(out.contains('₱'), isTrue);
    expect(out.replaceAll(RegExp(r'[^0-9.]'), ''), '1234.50');
  });

  test('formatCurrency renders minor units exactly', () {
    expect(formatCurrency(30).replaceAll(RegExp(r'[^0-9.]'), ''), endsWith('0.30'));
    expect(formatCurrency(1200).replaceAll(RegExp(r'[^0-9.]'), ''), '12.00');
  });

  test('formatDate renders full timestamp', () {
    final out = formatDate('2026-08-22T14:30:00.000');
    expect(out.contains('Aug'), isTrue);
    expect(out.contains('2026'), isTrue);
  });

  test('formatDateShort renders date only', () {
    final out = formatDateShort('2026-01-05T09:00:00.000');
    expect(out.contains('Jan'), isTrue);
    expect(out.contains('2026'), isTrue);
    expect(out.contains(':'), isFalse);
  });
}
