import 'package:flutter_test/flutter_test.dart';
import 'package:talako/utils/money.dart';

void main() {
  test('parseMajorToMinor parses and rounds half-up', () {
    expect(parseMajorToMinor('10.00'), 1000);
    expect(parseMajorToMinor('1.999'), 200);
    expect(parseMajorToMinor('0.1'), 10);
    expect(parseMajorToMinor('0.2'), 20);
    expect(parseMajorToMinor('123.456'), 12346);
    expect(parseMajorToMinor(' 1,234.50 '), 123450);
    expect(parseMajorToMinor('0.10')! + parseMajorToMinor('0.20')!, 30);
    expect(parseMajorToMinor('abc'), isNull);
    expect(parseMajorToMinor('1.2.3'), isNull);
  });

  test('formatMinorPlain renders editable major units', () {
    expect(formatMinorPlain(1234), '12.34');
    expect(formatMinorPlain(1000), '10');
    expect(formatMinorPlain(5), '0.05');
    expect(formatMinorPlain(-250), '-2.50');
  });

  test('isFullPayment is exact integer equality', () {
    expect(isFullPayment(3000, 3000), isTrue);
    expect(isFullPayment(2999, 3000), isFalse);
  });

  test('clampMinor bounds value', () {
    expect(clampMinor(-5, 0, 100), 0);
    expect(clampMinor(150, 0, 100), 100);
    expect(clampMinor(50, 0, 100), 50);
  });
}
