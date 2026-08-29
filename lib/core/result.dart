/// Failures the UI can branch on. Repositories throw these; Cubits catch them.
/// Anything not modelled here reaches the user as [AppStrings.somethingWentWrong].
sealed class AppFailure implements Exception {
  const AppFailure(this.message);
  final String message;

  // Defence in depth: `implements Exception` alone does not give a class a
  // human-readable toString -- without this, `'$e'` on any AppFailure prints
  // Object's default "Instance of 'ServerFailure'" straight to the user.
  // Every catch site is expected to read [message] directly rather than
  // rely on this, but a call site that slips back to `'$e'` still degrades
  // to something readable instead of a Dart type dump.
  @override
  String toString() => message;
}

/// No usable network connection, detected before the request was made.
final class OfflineFailure extends AppFailure {
  const OfflineFailure(super.message);
}

/// The server understood and refused. [code] is the SQLSTATE or the HTTP
/// status, kept because callers branch on specific ones (23505, 45002, 409).
final class ServerFailure extends AppFailure {
  const ServerFailure(super.message, {this.code});
  final String? code;
}

/// The session is missing or no longer valid.
final class AuthFailure extends AppFailure {
  const AuthFailure(super.message);
}

/// The user, the OS, or a device permission refused.
final class PermissionFailure extends AppFailure {
  const PermissionFailure(super.message);
}
