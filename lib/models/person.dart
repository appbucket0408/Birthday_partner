import '../api/api_params.dart';
import 'birthday.dart';

/// A row in public.people. `isClaimed` is whether the person has joined the
/// app. Only a claimed person has a birthday: nobody sets someone else's.
class Person {
  const Person({
    required this.id,
    required this.displayName,
    required this.isClaimed,
    this.birthday,
    this.profileId,
  });

  final int id;
  final String displayName;
  final bool isClaimed;
  final Birthday? birthday;

  /// Set only when claimed and the row was read with its profile_id.
  final String? profileId;

  factory Person.fromRow(Map<String, dynamic> row) => Person(
        id: row[ApiParams.id] as int,
        displayName: row[ApiParams.displayName] as String,
        isClaimed: row[ApiParams.profileId] != null,
        birthday: Birthday.fromRow(row),
        profileId: row[ApiParams.profileId] as String?,
      );
}
