import '../api/api_params.dart';

class BlockedUser {
  const BlockedUser({required this.profileId, required this.displayName});

  final String profileId;
  final String displayName;

  factory BlockedUser.fromRow(Map<String, dynamic> row) => BlockedUser(
        profileId: row[ApiParams.profileId] as String,
        displayName: row[ApiParams.displayName] as String,
      );
}
