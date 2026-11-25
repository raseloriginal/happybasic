import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bangladesh/core/format.dart';

void main() {
  test('Bangla digits and money', () {
    expect(bn(2026), '২০২৬');
    expect(money(1234567), '৳১২,৩৪,৫৬৭');
    expect(money(12.5), '৳১২.৫০');
    expect(dateBn('2026-11-25'), '২৫ নভেম্বর ২০২৬');
  });

  test('server numbers arrive as int, double or string', () {
    expect(num0('345.00'), 345.0);
    expect(num0(null), 0);
    expect(int0('12'), 12);
  });
}
