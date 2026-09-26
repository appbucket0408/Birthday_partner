import 'package:birthday_app/models/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parsePriceMinor accepts rupees with and without paise', () {
    expect(Product.parsePriceMinor('849'), 84900);
    expect(Product.parsePriceMinor('849.50'), 84950);
    // The zero-padding case, the mirror of priceLabel's own trap: a naive
    // parse of '849.5' yields 8495 rather than 84950.
    expect(Product.parsePriceMinor('849.5'), 84950);
    expect(Product.parsePriceMinor(' 849 '), 84900);
  });

  test('parsePriceMinor returns null for anything that is not a positive price',
      () {
    // products_price_positive is `check (price_minor > 0)` --
    // 20260822000006_catalog_slots.sql:21. Zero is NOT allowed.
    for (final bad in ['', '0', '0.00', '-5', 'abc', '8.499', '1,000']) {
      expect(Product.parsePriceMinor(bad), isNull,
          reason: 'should reject "$bad"');
    }
  });
}
