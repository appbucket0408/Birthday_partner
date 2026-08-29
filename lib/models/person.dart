import '../api/api_params.dart';
import 'birthday.dart';

/// A row in public.people. `isClaimed` decides whether this person's birthday
/// is editable: a claimed person owns their own date of birth, and
/// rpc_update_person_birthday refuses with 45003.
class Person {
  const Person({
    required this.id,
    required this.displayName,
    required this.isClaimed,
    this.birthday,
  });

  final int id;
  final String displayName;
  final bool isClaimed;
  final Birthday? birthday;

  factory Person.fromRow(Map<String, dynamic> row) => Person(
        id: row[ApiParams.id] as int,
        displayName: row[ApiParams.displayName] as String,
        isClaimed: row[ApiParams.profileId] != null,
        birthday: Birthday.fromRow(row),
      );
}
