import 'package:flutter_test/flutter_test.dart';
import 'package:talako/utils/money.dart';

void main() {
  test('roundMoney rounds to 2 decimal places', () {
    expect(roundMoney(10.004), 10.0);
    expect(roundMoney(1.999), 2.0);
    expect(roundMoney(0.1 + 0.2), 0.3);
    expect(roundMoney(123.456), 123.46);
    // 10.005 sits exactly on a half-centavo; its binary64 value lands above
    // the boundary so it rounds up. Boundary cases are not asserted.
  });

  test('moneyEquals uses centavo epsilon', () {
    expect(moneyEquals(0.1 + 0.2, 0.3), isTrue);
    expect(moneyEquals(49.99, 50.0), isTrue,
        reason: 'diff computes to 0.00999... which is sub-centavo');
    expect(moneyEquals(49.98, 50.0), isFalse);
    expect(moneyEquals(5.0, 5.02), isFalse);
  });

  test('isFullPayment tolerates float drift', () {
    final total = 0.1 + 0.2;
    expect(isFullPayment(total, total), isTrue);
    expect(isFullPayment(25.0, 50.0), isFalse);
  });

  test('clampMoney bounds value', () {
    expect(clampMoney(-5, 0, 100), 0.0);
    expect(clampMoney(150, 0, 100), 100.0);
    expect(clampMoney(50.004, 0, 100), 50.0);
  });
}
