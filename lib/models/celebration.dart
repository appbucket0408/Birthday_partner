import '../api/api_params.dart';
import 'person.dart';

/// An edge from the signed-in user to a person they celebrate, with the person
/// embedded. The person is always shown by their own name: there are no
/// nicknames (dropped in 20261017000002).
class Celebration {
  const Celebration({
    required this.id,
    required this.person,
  });

  final int id;
  final Person person;

  factory Celebration.fromRow(Map<String, dynamic> row) => Celebration(
        id: row[ApiParams.id] as int,
        person: Person.fromRow(row[ApiParams.people] as Map<String, dynamic>),
      );
}
