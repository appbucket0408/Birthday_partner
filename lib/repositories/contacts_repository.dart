import '../models/birthday.dart';
import '../models/import_outcome.dart';

/// A contact as it exists on the device, already normalised to E.164.
class DeviceContact {
  const DeviceContact({
    required this.name,
    required this.phoneE164,
    this.birthday,
  });

  final String name;
  final String phoneE164;
  final Birthday? birthday;

  DeviceContact withBirthday(Birthday? b) =>
      DeviceContact(name: name, phoneE164: phoneE164, birthday: b);
}

/// A number that already belongs to a person row on the server.
/// `hasBirthday` is what drives the fill-birthdays step: only contacts
/// without one need asking about.
class ResolvedContact {
  const ResolvedContact({
    required this.phone,
    required this.personId,
    required this.displayName,
    required this.hasBirthday,
  });

  final String phone;
  final int personId;
  final String displayName;
  final bool hasBirthday;
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
