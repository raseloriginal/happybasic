import 'package:flutter_test/flutter_test.dart';
import 'package:happy_bangladesh/core/format.dart';

void main() {
  test('Bangla digits and money (same output as the PWA)', () {
    expect(bn(2026), '২০২৬');
    expect(money(1234567), '৳১,২৩৪,৫৬৭'); // retailer panel: en-US grouping, no trailing .00
    expect(money(12.5), '৳১২.৫');
    expect(bnMoney(1234.5), '৳ ১,২৩৪.৫০'); // SR / DSR Bn::money
    expect(bnMoney(25, smart: true), '৳ ২৫');
    expect(signedMoney(-30, smart: true), '−৳ ৩০');
    expect(dateBn('2026-11-25'), '২৫ নভে ২০২৬');
    expect(dateLongBn('2026-11-22'), '২২ নভেম্বর ২০২৬');
    expect(timeBn('2026-11-25 14:03:00'), '২:০৩ PM');
  });

  test('server numbers arrive as int, double or string', () {
    expect(num0('345.00'), 345.0);
    expect(num0(null), 0);
    expect(int0('12'), 12);
  });
}
