import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Everything a contract test needs before it can reach a real local
/// Supabase instance from a `flutter test` process. None of the three fixes
/// below are optional and none are obvious -- Task 5 discovered all three
/// the hard way. Every contract test suite (auth, contacts, graph, settings)
/// must call [setUpContractTestEnvironment] as the first line of its
/// `setUpAll`, before constructing any Supabase client.
///
/// Requires the local stack: `supabase start` and `supabase functions serve`.

/// Undoes `flutter_test`'s fake-400 network stub and installs an in-memory
/// SharedPreferences store, so the client under test can make real HTTP
/// calls and supabase_flutter's session storage doesn't crash.
void setUpContractTestEnvironment() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // AutomatedTestWidgetsFlutterBinding installs an HttpOverrides that makes
  // every dart:io HttpClient (including the one under supabase_flutter's
  // gotrue/postgrest/functions clients) return a fake empty 400 with no
  // request ever leaving the process. These are contract tests against a
  // *real* local stack on purpose, so that override has to come back off.
  HttpOverrides.global = null;
  // `flutter test` also runs with no platform channels registered, so
  // supabase_flutter's default SharedPreferences-backed session storage
  // throws MissingPluginException. An in-memory implementation sidesteps
  // that without touching what the test verifies against real Supabase.
  SharedPreferencesStorePlatform.instance =
      InMemorySharedPreferencesStore.empty();
}

/// [auth.sms] max_frequency = "5s" rate-limits repeat sends to the SAME
/// number. Deleting an account resets its number's cooldown, but a test
/// that never completes verification (a wrong-code test, for instance)
/// leaves that number's cooldown running into whatever runs next. Route
/// every OTP send for a suite through one shared [OtpSendThrottle] instance
/// so back-to-back sends wait out any cooldown left by the previous one,
/// instead of intermittently 429ing and reading as a flaky suite.
class OtpSendThrottle {
  DateTime? _lastSentAt;

  /// Waits out any remaining cooldown, then runs [send].
  Future<void> run(Future<void> Function() send) async {
    final last = _lastSentAt;
    if (last != null) {
      const cooldown = Duration(seconds: 6);
      final elapsed = DateTime.now().difference(last);
      if (elapsed < cooldown) {
        await Future<void>.delayed(cooldown - elapsed);
      }
    }
    await send();
    _lastSentAt = DateTime.now();
  }
}

/// The 6-digit sign-in code in the newest mail to [email], read from
/// Mailpit -- the local inbox `supabase start` runs on port 54324, and the
/// only place a local email code goes.
///
/// The code in the newest mail to [email], polled briefly because
/// GoTrue hands the mail to Mailpit asynchronously.
Future<String> mailedCode(String email) async {
  final client = HttpClient();
  try {
    for (var attempt = 0; attempt < 20; attempt++) {
      final search = await _getJson(
        client,
        Uri.parse('http://127.0.0.1:54324/api/v1/search')
            .replace(queryParameters: {'query': 'to:$email'}),
      );
      final messages = search['messages'] as List;
      if (messages.isNotEmpty) {
        final id = (messages.first as Map<String, dynamic>)['ID'] as String;
        final message = await _getJson(
          client,
          Uri.parse('http://127.0.0.1:54324/api/v1/message/$id'),
        );
        final match = RegExp(r'\b(\d{6})\b').firstMatch(
          message['Text'] as String,
        );
        if (match != null) return match.group(1)!;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError('no code mailed to $email (is Mailpit on :54324?)');
  } finally {
    client.close();
  }
}

Future<Map<String, dynamic>> _getJson(HttpClient client, Uri uri) async {
  final res = await (await client.getUrl(uri)).close();
  return jsonDecode(await res.transform(utf8.decoder).join())
      as Map<String, dynamic>;
}
