import 'package:birthday_app/api/api_params.dart';
import 'package:birthday_app/models/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Product.fromRow', () {
    // `is_active` is `not null default true`
    // (20260822000006_catalog_slots.sql:19). The buyer's catalog never needed
    // it -- productsIn filters to active rows, so everything it maps is
    // active by definition. The ops console does need it: it must SHOW an
    // inactive product in order to reactivate one.
    test('maps is_active through, both ways', () {
      Product withActive(bool value) => Product.fromRow({
            ApiParams.id: 1,
            ApiParams.serviceAreaId: 1,
            ApiParams.name: 'Toggle Cake',
            ApiParams.flavour: null,
            ApiParams.size: null,
            ApiParams.priceMinor: 50000,
            ApiParams.imageUrl: null,
            ApiParams.isActive: value,
          });

      expect(withActive(true).isActive, isTrue);
      expect(withActive(false).isActive, isFalse);
    });

    // Every existing caller builds rows without the column (the buyer's
    // reads predate it), and `not null default true` means a real row always
    // carries one. Defaulting to true keeps those call sites working rather
    // than making the field nullable, which would push a null check into
    // every consumer for a column the database guarantees.
    test('a row omitting is_active defaults to active', () {
      final product = Product.fromRow({
        ApiParams.id: 1,
        ApiParams.serviceAreaId: 1,
        ApiParams.name: 'Legacy Cake',
        ApiParams.flavour: null,
        ApiParams.size: null,
        ApiParams.priceMinor: 50000,
        ApiParams.imageUrl: null,
      });

      expect(product.isActive, isTrue);
    });

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

  // price_minor is paise, `bigint not null check (price_minor > 0)` per
  // supabase/migrations/20260822000006_catalog_slots.sql -- no negative or
  // zero cases exist, so priceLabel need not handle either.
  group('Product.priceLabel', () {
    Product withPrice(int minor) => Product(
          id: 1,
          serviceAreaId: 1,
          name: 'Test Cake',
          flavour: null,
          size: null,
          priceMinor: minor,
          imageUrl: null,
        );

    test('a whole-rupee amount renders with no decimals', () {
      expect(withPrice(84900).priceLabel, '₹849');
    });

    test('a half-rupee amount renders with two decimals', () {
      expect(withPrice(84950).priceLabel, '₹849.50');
    });

    // The discriminating case: a naive '₹$rupees.$paise' implementation
    // renders '₹849.5', dropping the trailing zero. No thousands separator
    // either -- Indian grouping is lakh/crore, not the three-digit grouping
    // a naive formatter would produce, so plain digits are correct here.
    test('a single-digit paise remainder is zero-padded to two digits', () {
      expect(withPrice(84905).priceLabel, '₹849.05');
    });
  });
}
