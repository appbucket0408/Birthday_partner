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
final class ImportPicking extends ImportState {
  const ImportPicking({
    required this.contacts,
    required this.resolved,
    required this.selected,
    this.celebrating = const {},
  });

  final List<DeviceContact> contacts;
  final List<ResolvedContact> resolved;
  final Set<String> selected;
  final Set<int> celebrating;

  ResolvedContact? resolvedFor(String phoneE164) {
    for (final r in resolved) {
      if (r.phone == phoneE164) return r;
    }
    return null;
  }

  bool isMember(String phoneE164) => resolvedFor(phoneE164)?.isMember ?? false;

  bool isCelebrating(String phoneE164) {
    final r = resolvedFor(phoneE164);
    return r != null && celebrating.contains(r.personId);
  }
}

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
