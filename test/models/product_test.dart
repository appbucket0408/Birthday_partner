import 'package:birthday_app/api/api_params.dart';
import 'package:birthday_app/models/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Product.fromRow', () {
    test('a row with flavour and size present maps them through', () {
      final product = Product.fromRow({
        ApiParams.id: 1,
        ApiParams.serviceAreaId: 1,
        ApiParams.name: 'Classic Chocolate Truffle',
        ApiParams.flavour: 'chocolate',
        ApiParams.size: '500g',
        ApiParams.priceMinor: 84900,
        ApiParams.imageUrl: 'https://example.com/cake.jpg',
      });

      expect(product.flavour, 'chocolate');
      expect(product.size, '500g');
    });

    // supabase/migrations/20260822000006_catalog_slots.sql declares flavour
    // and size with no `not null` — a staff-inserted catalog row can omit
    // either. This is the regression guard: fromRow must map a null straight
    // through rather than a failed cast aborting the whole service area's
    // catalog.
    test('a row with both null maps to null and does not throw', () {
      final product = Product.fromRow({
        ApiParams.id: 1,
        ApiParams.serviceAreaId: 1,
        ApiParams.name: 'Mystery Cake',
        ApiParams.flavour: null,
        ApiParams.size: null,
        ApiParams.priceMinor: 50000,
        ApiParams.imageUrl: null,
      });

      expect(product.flavour, isNull);
      expect(product.size, isNull);
    });
  });
}
