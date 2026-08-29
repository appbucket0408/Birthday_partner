import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_strings.dart';
import '../core/result.dart';

/// Turns the client's exception zoo into the four failures the UI branches on.
///
/// SQLSTATE survives into [ServerFailure.code] deliberately: docs/db.md records
/// that the codes are a public API decision, and callers branch on specific
/// ones -- 23505 for a taken handle, 45002/45003 for the birthday-edit guards.
AppFailure mapError(Object error) {
  if (error is AppFailure) return error;

  if (error is AuthException) {
    return AuthFailure(error.message);
  }
  if (error is PostgrestException) {
    return ServerFailure(error.message, code: error.code);
  }
  if (error is FunctionException) {
    final detail = error.details;
    final message = detail is Map && detail['error'] is String
        ? detail['error'] as String
        : AppStrings.somethingWentWrong;
    return ServerFailure(message, code: '${error.status}');
  }
  return ServerFailure(AppStrings.somethingWentWrong);
}
