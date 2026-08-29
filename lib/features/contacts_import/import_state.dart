import '../../models/birthday.dart';
import '../../models/import_outcome.dart';
import '../../repositories/contacts_repository.dart';

sealed class ImportState {
  const ImportState();
}

final class ImportIdle extends ImportState {
  const ImportIdle();
}

final class ImportRequestingPermission extends ImportState {
  const ImportRequestingPermission();
}

final class ImportPermissionDenied extends ImportState {
  const ImportPermissionDenied();
}

final class ImportLoadingContacts extends ImportState {
  const ImportLoadingContacts();
}

/// The pick screen's state. [birthdays] is what the fill-birthdays screen
/// writes into via [ImportCubit.setBirthday] before commit -- it lives here,
/// not in a state of its own, because there is no dedicated "filling"
/// state in the parent spec's state machine.
final class ImportPicking extends ImportState {
  const ImportPicking({
    required this.contacts,
    required this.resolved,
    required this.selected,
    this.birthdays = const {},
  });

  final List<DeviceContact> contacts;
  final List<ResolvedContact> resolved;
  final Set<String> selected;
  final Map<String, Birthday> birthdays;

  /// True when neither the device address book nor the server has a
  /// birthday for this phone, and the fill-birthdays screen has not filled
  /// one in either. Drives both the pick screen's "no birthday" note and the
  /// fill screen's contact list.
  bool needsBirthday(String phoneE164) {
    if (birthdays.containsKey(phoneE164)) return false;
    for (final c in contacts) {
      if (c.phoneE164 == phoneE164) {
        if (c.birthday != null) return false;
        break;
      }
    }
    for (final r in resolved) {
      if (r.phone == phoneE164) return !r.hasBirthday;
    }
    return true;
  }

  /// Selected contacts with no birthday anywhere -- what the fill-birthdays
  /// screen shows. Shrinks live as the user answers each one.
  List<String> get missingBirthdays =>
      selected.where(needsBirthday).toList(growable: false);
}

/// [done]/[total] mirror the repository's chunk progress, not a per-contact
/// count -- see ContactsRepository.addCelebrations.
final class ImportCommitting extends ImportState {
  const ImportCommitting(this.done, this.total);
  final int done;
  final int total;
}

final class ImportDone extends ImportState {
  const ImportDone(this.summary);
  final ImportSummary summary;
}

final class ImportFailed extends ImportState {
  const ImportFailed(this.message);
  final String message;
}
