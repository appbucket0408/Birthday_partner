import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import '../../api/api_client.dart';
import '../../models/birthday.dart';
import '../../repositories/contacts_repository.dart';
import 'import_state.dart';

class ImportCubit extends Cubit<ImportState> {
  ImportCubit(this._contactsRepo) : super(const ImportIdle());
  final ContactsRepository _contactsRepo;

  // The picked-contacts/selection/birthdays live here, not just in
  // ImportPicking, so commit() can be re-run from the summary screen's
  // retry after the displayed state has already moved on to ImportDone or
  // ImportFailed.
  List<DeviceContact> _contacts = const [];
  List<ResolvedContact> _resolved = const [];
  Set<String> _selected = {};
  final Map<String, Birthday> _birthdays = {};

  /// Must not touch any permission API until this is called -- Play requires
  /// the disclosure screen to precede the OS prompt, and this is the only
  /// entry point that reaches [ContactsRepository.requestPermission].
  Future<void> start() async {
    emit(const ImportRequestingPermission());
    final granted = await _contactsRepo.requestPermission();
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
    // Opt in, never opt out, for a screen that mints rows: nothing is
    // selected until the user picks it.
    _selected = {};
    _emitPicking();
  }

  void toggle(String phoneE164) {
    if (!_selected.remove(phoneE164)) _selected.add(phoneE164);
    _emitPicking();
  }

  void setBirthday(String phoneE164, Birthday? birthday) {
    if (birthday == null) {
      _birthdays.remove(phoneE164);
    } else {
      _birthdays[phoneE164] = birthday;
    }
    _emitPicking();
  }

  void _emitPicking() {
    emit(ImportPicking(
      contacts: _contacts,
      resolved: _resolved,
      selected: Set.unmodifiable(_selected),
      birthdays: Map.unmodifiable(_birthdays),
    ));
  }

  /// Create-on-select: sends ONLY the contacts the user picked. A person row
  /// must never be minted for a non-consenting contact just because it sat
  /// in someone's address book.
  Future<void> commit() async {
    final toSend = _contacts
        .where((c) => _selected.contains(c.phoneE164))
        .map((c) {
          final filled = _birthdays[c.phoneE164];
          return filled == null ? c : c.withBirthday(filled);
        })
        .toList(growable: false);

    try {
      final summary = await _contactsRepo.addCelebrations(
        toSend,
        onProgress: (done, total) => emit(ImportCommitting(done, total)),
      );
      emit(ImportDone(summary));
    } catch (e) {
      emit(ImportFailed('$e'));
    }
  }

  /// The parent spec says "against the country captured at onboarding", but
  /// onboarding never captures a country -- PhoneCubit.submitPhone merely
  /// defaults isoCode to 'IN', so there is nothing stored to read. Derived
  /// instead from the signed-in user's own verified E.164 phone, which
  /// Supabase stores WITHOUT a leading '+'.
  ///
  /// Wrapped defensively: under `flutter test` Supabase is never
  /// initialised, so ApiClient.instance itself throws. That is exactly the
  /// "absent" case the parent spec already asks to fall back on, so it is
  /// folded into the same catch as an unparseable number rather than given
  /// special handling.
  static String _regionIsoCode() {
    try {
      final raw = ApiClient.instance.auth.currentUser?.phone;
      if (raw == null || raw.isEmpty) return 'IN';
      return PhoneNumber.parse('+$raw').isoCode.name;
    } catch (_) {
      return 'IN';
    }
  }
}
