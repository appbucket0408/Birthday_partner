import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import '../../api/api_client.dart';
import '../../core/app_strings.dart';
import '../../core/logger.dart';
import '../../core/result.dart';
import '../../models/birthday.dart';
import '../../repositories/contacts_repository.dart';
import 'import_state.dart';

class ImportCubit extends Cubit<ImportState> {
  /// [currentUserPhone] is injectable so tests can supply a phone string
  /// without initialising Supabase -- it defaults to the live lookup used
  /// in production. See [_regionIsoCode].
  ImportCubit(this._contactsRepo, {String? Function()? currentUserPhone})
      : _currentUserPhone = currentUserPhone ?? _liveCurrentUserPhone,
        super(const ImportIdle());

  final ContactsRepository _contactsRepo;
  final String? Function() _currentUserPhone;

  static String? _liveCurrentUserPhone() =>
      ApiClient.instance.auth.currentUser?.phone;

  // The picked-contacts/selection/birthdays live here, not just in
  // ImportPicking, so commit() can be re-run from the summary screen's
  // retry after the displayed state has already moved on to ImportDone or
  // ImportFailed.
  List<DeviceContact> _contacts = const [];
  List<ResolvedContact> _resolved = const [];
  Set<String> _selected = {};
  final Map<String, Birthday> _birthdays = {};

  // Guards commit(), not just recorded in state: ImportCommitting is only
  // emitted from the repository's first onProgress callback, so relying on
  // `state is ImportCommitting` would leave the whole window between tap
  // and that first callback unguarded -- exactly where a fast double-tap on
  // add_selected / fill_continue / summary_retry lands.
  bool _committing = false;

  /// Must not touch any permission API until this is called -- Play requires
  /// the disclosure screen to precede the OS prompt, and this is the only
  /// entry point that reaches [ContactsRepository.requestPermission].
  Future<void> start() async {
    emit(const ImportRequestingPermission());
    try {
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
    } on AppFailure catch (f) {
      emit(ImportFailed(f.message));
    } catch (_) {
      // Neither requestPermission(), readDeviceContacts() nor resolve() was
      // caught here before -- a failure of any of the three left the cubit
      // stuck in ImportLoadingContacts, which the disclosure screen renders
      // as a permanently-disabled spinner: no error, no retry, no way off
      // the screen. commit() already has this same catch-all twelve lines
      // below; start() needs it just as much.
      emit(const ImportFailed(AppStrings.somethingWentWrong));
    }
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
  ///
  /// A second call while one is already in flight (a fast double-tap on any
  /// of the three buttons that call this) is a no-op: the cubit, not its
  /// callers, owns what is in flight.
  Future<void> commit() async {
    if (_committing) return;
    _committing = true;
    try {
      final toSend = _contacts
          .where((c) => _selected.contains(c.phoneE164))
          .map((c) {
            final filled = _birthdays[c.phoneE164];
            return filled == null ? c : c.withBirthday(filled);
          })
          .toList(growable: false);

      final summary = await _contactsRepo.addCelebrations(
        toSend,
        onProgress: (done, total) => emit(ImportCommitting(done, total)),
      );
      emit(ImportDone(summary));
    } on AppFailure catch (f) {
      emit(ImportFailed(f.message));
    } catch (_) {
      emit(const ImportFailed(AppStrings.somethingWentWrong));
    } finally {
      _committing = false;
    }
  }

  /// The parent spec says "against the country captured at onboarding", but
  /// onboarding never captures a country -- PhoneCubit.submitPhone merely
  /// defaults isoCode to 'IN', so there is nothing stored to read. Derived
  /// instead from the signed-in user's own verified E.164 phone, which
  /// Supabase stores WITHOUT a leading '+'.
  ///
  /// Two distinct failure modes, handled differently:
  ///  - Reaching the phone at all can fail (no session, or -- under
  ///    `flutter test` -- Supabase never initialised). There is no region to
  ///    derive either way, so this falls back to 'IN' silently; it is
  ///    expected, not a bug.
  ///  - Parsing a phone that WAS reached can fail. That phone already
  ///    passed PhoneNumber.parse once, in PhoneCubit.submitPhone, to get a
  ///    verified session in the first place, so a parse failure here is
  ///    unexpected and is logged rather than swallowed.
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
