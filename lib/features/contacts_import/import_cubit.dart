import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import '../../api/api_client.dart';
import '../../core/analytics.dart';
import '../../core/app_strings.dart';
import '../../core/logger.dart';
import '../../core/result.dart';
import '../../repositories/contacts_repository.dart';
import 'import_state.dart';

class ImportCubit extends Cubit<ImportState> {
  ImportCubit(
    this._contactsRepo, {
    String? Function()? currentUserPhone,
    Future<Set<int>> Function()? alreadyCelebrating,
  })  : _currentUserPhone = currentUserPhone ?? _liveCurrentUserPhone,
        _alreadyCelebrating = alreadyCelebrating,
        super(const ImportIdle());

  final ContactsRepository _contactsRepo;
  final String? Function() _currentUserPhone;
  final Future<Set<int>> Function()? _alreadyCelebrating;
  Set<int> _celebrating = const {};

  static String? _liveCurrentUserPhone() =>
      ApiClient.instance.auth.currentUser?.phone;
  List<DeviceContact> _contacts = const [];
  List<ResolvedContact> _resolved = const [];
  Set<String> _selected = {};
  bool _committing = false;
  Future<void> start() async {
    emit(const ImportRequestingPermission());
    try {
      final granted = await _contactsRepo.requestPermission();
      Analytics.contactsPermission(granted: granted).ignore();
      if (!granted) {
        emit(const ImportPermissionDenied());
        return;
      }

      emit(const ImportLoadingContacts());
      _contacts = await _contactsRepo.readDeviceContacts(
        isoCode: _regionIsoCode(),
      );
      _resolved = await _contactsRepo.resolve(
        _contacts.map((c) => c.phoneE164).toList(),
      );
      try {
        _celebrating = await _alreadyCelebrating?.call() ?? const {};
      } catch (_) {
        _celebrating = const {};
      }

      _selected = {};
      _emitPicking();
    } on AppFailure catch (f) {
      emit(ImportFailed(f.message));
    } catch (_) {
      emit(const ImportFailed(AppStrings.somethingWentWrong));
    }
  }

  void toggle(String phoneE164) {
    if (!_selected.remove(phoneE164)) _selected.add(phoneE164);
    _emitPicking();
  }

  /// Selects (or clears) several at once -- a section's "Select all".
  void setSelected(Iterable<String> phonesE164, {required bool selected}) {
    if (selected) {
      _selected.addAll(phonesE164);
    } else {
      _selected.removeAll(phonesE164);
    }
    _emitPicking();
  }

  void _emitPicking() {
    emit(ImportPicking(
      contacts: _contacts,
      resolved: _resolved,
      selected: Set.unmodifiable(_selected),
      celebrating: _celebrating,
    ));
  }

  Future<void> commit() async {
    if (_committing) return;
    _committing = true;
    try {
      final toSend = _contacts
          .where((c) => _selected.contains(c.phoneE164))
          .toList(growable: false);

      final summary = await _contactsRepo.addCelebrations(
        toSend,
        onProgress: (done, total) => emit(ImportCommitting(done, total)),
      );
      Analytics.contactsImported(summary.added).ignore();
      emit(ImportDone(summary));
    } on AppFailure catch (f) {
      emit(ImportFailed(f.message));
    } catch (_) {
      emit(const ImportFailed(AppStrings.somethingWentWrong));
    } finally {
      _committing = false;
    }
  }
  String _regionIsoCode() {
    String? raw;
    try {
      raw = _currentUserPhone();
    } catch (_) {
      return 'IN';
    }
    if (raw == null || raw.isEmpty) return 'IN';

    try {
      return PhoneNumber.parse('+$raw').isoCode.name;
    } catch (e) {
      Log.error('failed to parse current user phone for import region', e);
      return 'IN';
    }
  }
}
