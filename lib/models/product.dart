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
  });

  final int id;
  final int serviceAreaId;
  final String name;
  final String? flavour;
  final String? size;
  final int priceMinor;
  final String? imageUrl;

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

  factory Product.fromRow(Map<String, dynamic> row) => Product(
        id: row[ApiParams.id] as int,
        serviceAreaId: row[ApiParams.serviceAreaId] as int,
        name: row[ApiParams.name] as String,
        flavour: row[ApiParams.flavour] as String?,
        size: row[ApiParams.size] as String?,
        priceMinor: row[ApiParams.priceMinor] as int,
        imageUrl: row[ApiParams.imageUrl] as String?,
      );
}
