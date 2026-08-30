import '../api/api_params.dart';

/// A delivery window. `remaining` is public information — it is a van's
/// schedule, not anyone's personal data — so the picker shows it.
class DeliverySlot {
  const DeliverySlot({
    required this.id,
    required this.serviceAreaId,
    required this.slotDate,
    required this.windowStart,
    required this.windowEnd,
    required this.capacity,
    required this.reserved,
  });

  final int id;
  final int serviceAreaId;
  final DateTime slotDate;
  final String windowStart;
  final String windowEnd;
  final int capacity;
  final int reserved;

  /// Clamped at zero. `delivery_slots_not_oversold` makes a negative
  /// impossible in the database, but a client must never render one.
  int get remaining => (capacity - reserved).clamp(0, capacity);

  bool get isBookable => remaining > 0;

  factory DeliverySlot.fromRow(Map<String, dynamic> row) => DeliverySlot(
        id: row[ApiParams.id] as int,
        serviceAreaId: row[ApiParams.serviceAreaId] as int,
        slotDate: DateTime.parse(row[ApiParams.slotDate] as String),
        windowStart: row[ApiParams.windowStart] as String,
        windowEnd: row[ApiParams.windowEnd] as String,
        capacity: row[ApiParams.capacity] as int,
        reserved: row[ApiParams.reserved] as int,
      );
}
