import '../api/api_params.dart';

/// A row in public.products — a cake catalog item scoped to a service area.
///
/// [priceMinor] stays an int of minor units (paise); [priceLabel] is the
/// only place that converts it for display, so the rule sits with the value
/// object rather than being re-derived (and re-broken) in the screen.
class Product {
  const Product({
    required this.id,
    required this.serviceAreaId,
    required this.name,
    required this.flavour,
    required this.size,
    required this.priceMinor,
    required this.imageUrl,
    this.isActive = true,
  });

  final int id;
  final int serviceAreaId;
  final String name;
  final String? flavour;
  final String? size;
  final int priceMinor;
  final String? imageUrl;

  /// `is_active` is `not null default true`
  /// (20260822000006_catalog_slots.sql:19). Non-nullable here with a `true`
  /// default rather than `bool?`: the database guarantees a value, so a
  /// nullable field would push a null check into every consumer for a case
  /// that cannot occur. The default also keeps the buyer's existing reads
  /// working -- GiftRepository.productsIn filters to active rows, so every
  /// product it maps is active by definition and never sent the column.
  final bool isActive;

  /// `priceMinor` in rupees and paise, integer arithmetic only -- no `intl`
  /// dependency for one helper, and no thousands separator (Indian grouping
  /// is lakh/crore, not the three-digit grouping a naive formatter would
  /// produce, and a wrong separator reads worse than plain digits). A zero
  /// paise remainder renders with no decimals; otherwise exactly two,
  /// zero-padded -- `84905` (₹849 and 5 paise) must read '₹849.05', not the
  /// '₹849.5' a bare string interpolation of the remainder would produce.
  String get priceLabel {
    final rupees = priceMinor ~/ 100;
    final paise = priceMinor % 100;
    if (paise == 0) return '₹$rupees';
    return '₹$rupees.${paise.toString().padLeft(2, '0')}';
  }

  /// [priceLabel]'s inverse: rupees typed by a human into paise for the
  /// database. Lives beside it so the two rules cannot drift apart.
  ///
  /// Returns null rather than throwing, and null means "not a price the
  /// database would accept". The ops console turns that into its own
  /// message, because `products_price_positive check (price_minor > 0)`
  /// (20260822000006_catalog_slots.sql:21) would otherwise answer with a
  /// bare 23514 -- the generic CHECK code this schema already shares with
  /// the slot window-order, not-oversold and capacity constraints, so the
  /// caller could not tell which rule it tripped.
  ///
  /// Zero is rejected deliberately: the constraint is `> 0`, not `>= 0`.
  /// At most two decimal places -- paise is the smallest unit, and
  /// accepting '8.499' would silently round money.
  static int? parsePriceMinor(String input) {
    final trimmed = input.trim();
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(trimmed)) return null;

    final parts = trimmed.split('.');
    final rupees = int.parse(parts[0]);
    // '849.5' is 50 paise, not 5 -- padRight, the mirror of priceLabel's
    // padLeft. Getting this backwards turns ₹849.50 into ₹849.05.
    final paise =
        parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0;

    final total = rupees * 100 + paise;
    return total > 0 ? total : null;
  }

  factory Product.fromRow(Map<String, dynamic> row) => Product(
        id: row[ApiParams.id] as int,
        serviceAreaId: row[ApiParams.serviceAreaId] as int,
        name: row[ApiParams.name] as String,
        flavour: row[ApiParams.flavour] as String?,
        size: row[ApiParams.size] as String?,
        priceMinor: row[ApiParams.priceMinor] as int,
        imageUrl: row[ApiParams.imageUrl] as String?,
        isActive: (row[ApiParams.isActive] as bool?) ?? true,
      );
}
