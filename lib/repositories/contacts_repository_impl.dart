import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:phone_numbers_parser/phone_numbers_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_endpoints.dart';
import '../api/api_error_mapper.dart';
import '../core/logger.dart';
import '../models/import_outcome.dart';
import 'contacts_repository.dart';

class ContactsRepositoryImpl implements ContactsRepository {
  const ContactsRepositoryImpl(this._client);
  final SupabaseClient _client;

  static const _maxBatch = 500;

  @override
  Future<bool> requestPermission() =>
      fc.FlutterContacts.requestPermission(readonly: true);

  @override
  Future<List<DeviceContact>> readDeviceContacts({
    String isoCode = 'IN',
  }) async {
    final raw = await fc.FlutterContacts.getContacts(
      withProperties: true,
      withPhoto: false,
    );

    final out = <DeviceContact>[];
    final seen = <String>{};
    for (final c in raw) {
      final name = c.displayName.trim();
      if (name.isEmpty) continue;

      for (final phone in c.phones) {
        final e164 = _toE164(phone.number, isoCode);
        // A number that cannot be parsed is dropped here rather than sent.
        // The server would answer invalid_phone, but a device contact with a
        // landline is not a failure worth showing the user.
        if (e164 == null || !seen.add(e164)) continue;
        out.add(DeviceContact(name: name, phoneE164: e164));
      }
    }
    return out;
  }

  static String? _toE164(String raw, String isoCode) {
    try {
      final parsed = PhoneNumber.parse(
        raw,
        callerCountry: IsoCode.values.byName(isoCode),
      );
      return parsed.isValid() ? '+${parsed.countryCode}${parsed.nsn}' : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<ResolvedContact>> resolve(List<String> phonesE164) async {
    final out = <ResolvedContact>[];
    for (final chunk in _chunks(phonesE164, _maxBatch)) {
      try {
        final res = await _client.functions.invoke(
          ApiEndpoints.resolveContacts,
          body: {'phones': chunk},
        );
        final matches = (res.data as Map<String, dynamic>)['matches'] as List;
        out.addAll(matches.map((m) {
          final row = m as Map<String, dynamic>;
          return ResolvedContact(
            phone: row['phone'] as String,
            personId: row['person_id'] as int,
            displayName: row['display_name'] as String,
            isMember: row['is_member'] as bool,
          );
        }));
      } catch (e) {
        throw mapError(e);
      }
    }
    return out;
  }

  @override
  Future<ImportSummary> addCelebrations(
    List<DeviceContact> contacts, {
    int chunkSize = _maxBatch,
    void Function(int done, int total)? onProgress,
  }) async {
    var summary = ImportSummary.empty;
    var done = 0;

    for (final chunk in _chunks(contacts, chunkSize)) {
      try {
        final res = await _client.functions.invoke(
          ApiEndpoints.addCelebrations,
          body: {
            'contacts': chunk
                .map((c) => {
                      'phone': c.phoneE164,
                      'name': c.name,
                    })
                .toList(),
          },
        );
        final body = res.data as Map<String, dynamic>;
        summary = summary.merge(ImportSummary(
          added: body['added'] as int,
          skipped: body['skipped'] as int,
          failed: body['failed'] as int,
          duplicates: body['duplicates'] as int,
          results: (body['results'] as List)
              .map((r) => ImportOutcome.fromRow(r as Map<String, dynamic>))
              .toList(),
        ));
      } catch (e) {
        // One bad chunk must not lose the chunks that already succeeded, and
        // must not silently shorten `results` -- the summary screen zips it
        // positionally against the picked list.
        Log.error('import chunk failed', e);
        summary = summary.merge(ImportSummary(
          added: 0,
          skipped: 0,
          failed: chunk.length,
          duplicates: 0,
          results: chunk
              .map((c) => ImportOutcome(
                    phone: c.phoneE164,
                    personId: null,
                    status: ImportStatus.failed,
                  ))
              .toList(),
        ));
      }
      done += chunk.length;
      onProgress?.call(done, contacts.length);
    }
    return summary;
  }

  static Iterable<List<T>> _chunks<T>(List<T> items, int size) sync* {
    for (var i = 0; i < items.length; i += size) {
      yield items.sublist(
        i,
        i + size > items.length ? items.length : i + size,
      );
    }
  }
}
