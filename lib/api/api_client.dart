import 'package:supabase_flutter/supabase_flutter.dart';

/// The Supabase singleton. Defaults point at the local stack, so a developer
/// with `supabase start` running needs no --dart-define at all.
abstract final class ApiClient {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:54321',
  );
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// [anonKey] has no `defaultValue`, so a run without the dart-define
  /// silently resolves it to `''`. `Supabase.initialize` accepts that without
  /// complaint and every request then fails much later with an opaque 401
  /// that looks like a credentials or RLS problem. Fail loudly here instead.
  static Future<void> init() {
    if (anonKey.isEmpty) {
      throw StateError(
        'SUPABASE_ANON_KEY is empty. Pass it with '
        '--dart-define=SUPABASE_ANON_KEY=<key>.',
      );
    }
    return Supabase.initialize(url: url, publishableKey: anonKey).then(
      (_) {},
    );
  }

  static SupabaseClient get instance => Supabase.instance.client;
}
