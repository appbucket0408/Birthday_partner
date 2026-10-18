import '../api/api_params.dart';
import 'birthday.dart';


class Person {
  const Person({
    required this.id,
    required this.displayName,
    required this.isClaimed,
    this.profileId,
    this.birthday,
  });

  final int id;
  final String displayName;
  final bool isClaimed;

  /// The member's profile, for report and block. Null until they join.
  final String? profileId;
  final Birthday? birthday;

  factory Person.fromRow(Map<String, dynamic> row) => Person(
        id: row[ApiParams.id] as int,
        displayName: row[ApiParams.displayName] as String,
        isClaimed: row[ApiParams.profileId] != null,
        profileId: row[ApiParams.profileId] as String?,
        birthday: Birthday.fromRow(row),
      );
}
