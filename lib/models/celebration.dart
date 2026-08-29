import '../api/api_params.dart';
import 'person.dart';

/// An edge from the signed-in user to a person they celebrate, with the person
/// embedded. `nickname` overrides the address-book name in the UI.
class Celebration {
  const Celebration({
    required this.id,
    required this.person,
    this.nickname,
  });

  final int id;
  final Person person;
  final String? nickname;

  String get label => nickname ?? person.displayName;

  factory Celebration.fromRow(Map<String, dynamic> row) => Celebration(
        id: row[ApiParams.id] as int,
        nickname: row[ApiParams.nickname] as String?,
        person: Person.fromRow(row[ApiParams.people] as Map<String, dynamic>),
      );
}
