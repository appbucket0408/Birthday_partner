import '../../models/delivery_slot.dart';
import '../../models/service_area.dart';

sealed class OpsSlotsState {
  const OpsSlotsState();
}

class OpsSlotsLoading extends OpsSlotsState {
  const OpsSlotsLoading();
}

/// [from] and [to] are the range the screen is showing, held here rather
/// than in the widget so a reload after a mutation reuses exactly the range
/// the user chose -- and never a range derived from the client's clock.
class OpsSlotsLoaded extends OpsSlotsState {
  const OpsSlotsLoaded({
    required this.areas,
    required this.selectedAreaId,
    required this.from,
    required this.to,
    required this.slots,
  });

  final List<ServiceArea> areas;
  final int? selectedAreaId;
  final DateTime from;
  final DateTime to;
  final List<DeliverySlot> slots;

  OpsSlotsLoaded copyWith({
    int? selectedAreaId,
    DateTime? from,
    DateTime? to,
    List<DeliverySlot>? slots,
  }) =>
      OpsSlotsLoaded(
        areas: areas,
        selectedAreaId: selectedAreaId ?? this.selectedAreaId,
        from: from ?? this.from,
        to: to ?? this.to,
        slots: slots ?? this.slots,
      );
}

class OpsSlotsError extends OpsSlotsState {
  const OpsSlotsError(this.message);
  final String message;
}
