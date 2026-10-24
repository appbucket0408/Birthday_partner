import '../api/api_params.dart';

class BlockedPerson {
  const BlockedPerson({required this.profileId, required this.displayName});

  final String profileId;
  final String displayName;

  factory BlockedPerson.fromRow(Map<String, dynamic> row) => BlockedPerson(
        profileId: row[ApiParams.profileId] as String,
        displayName: row[ApiParams.displayName] as String,
      );
}
