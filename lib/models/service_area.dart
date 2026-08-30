import '../api/api_params.dart';

/// A row in public.service_areas — the set of localities gifting is offered
/// in.
class ServiceArea {
  const ServiceArea({
    required this.id,
    required this.name,
  });

  final int id;
  final String name;

  factory ServiceArea.fromRow(Map<String, dynamic> row) => ServiceArea(
        id: row[ApiParams.id] as int,
        name: row[ApiParams.name] as String,
      );
}
