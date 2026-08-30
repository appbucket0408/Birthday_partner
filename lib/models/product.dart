import '../api/api_params.dart';

/// A row in public.products — a cake catalog item scoped to a service area.
///
/// [priceMinor] stays an int of minor units (e.g. paise); no currency
/// formatting belongs on this model — that is a later `priceLabel` helper's
/// job, not this one's.
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
