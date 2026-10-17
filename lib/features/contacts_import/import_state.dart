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

/// The pick screen's state.
final class ImportPicking extends ImportState {
  const ImportPicking({
    required this.contacts,
    required this.resolved,
    required this.selected,
  });

  final List<DeviceContact> contacts;
  final List<ResolvedContact> resolved;
  final Set<String> selected;
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
