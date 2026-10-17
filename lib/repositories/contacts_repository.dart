import '../models/import_outcome.dart';

/// A contact as it exists on the device, already normalised to E.164. Name
/// and number only: the address book's birthday is never read, because only
/// a person sets their own.
class DeviceContact {
  const DeviceContact({required this.name, required this.phoneE164});

  final String name;
  final String phoneE164;
}

/// A number that already belongs to a person row on the server.
class ResolvedContact {
  const ResolvedContact({
    required this.phone,
    required this.personId,
    required this.displayName,
  });

  final String phone;
  final int personId;
  final String displayName;
}

abstract interface class ContactsRepository {
  /// Must be called only AFTER the prominent-disclosure screen. Play requires
  /// the disclosure to precede the OS prompt.
  Future<bool> requestPermission();

  Future<List<DeviceContact>> readDeviceContacts({String isoCode = 'IN'});

  /// Match-only. Creates nothing: a person row is minted when the user picks
  /// someone, not when they import their address book.
  Future<List<ResolvedContact>> resolve(List<String> phonesE164);

  /// Commits the picked contacts, chunked. [onProgress] fires once per chunk
  /// with (done, total).
  Future<ImportSummary> addCelebrations(
    List<DeviceContact> contacts, {
    int chunkSize,
    void Function(int done, int total)? onProgress,
  });
}
