import 'package:supabase_flutter/supabase_flutter.dart';

/// The Supabase singleton. Defaults point at the local stack, so a developer
/// with `supabase start` running needs no --dart-define at all.
abstract final class ApiClient {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:54321',
  );
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static Future<void> init() =>
      Supabase.initialize(url: url, publishableKey: anonKey).then((_) {});

  static SupabaseClient get instance => Supabase.instance.client;
}
