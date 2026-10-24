import '../api/api_params.dart';

/// A member seen on the public feed but not connected to the viewer.
/// No birthday: that is shared only once the viewer celebrates them.
class MemberPreview {
  const MemberPreview({
    required this.id,
    required this.displayName,
    required this.celebratorCount,
    this.handle,
    this.mutualCount = 0,
  });

  final int id;
  final String displayName;
  final int celebratorCount;

  /// Null while they still have the signup placeholder.
  final String? handle;

  /// How many people the viewer celebrates also celebrate them.
  final int mutualCount;

  factory MemberPreview.fromRow(Map<String, dynamic> row) => MemberPreview(
    id: row[ApiParams.id] as int,
    displayName: row[ApiParams.displayName] as String,
    celebratorCount: row[ApiParams.celebratorCount] as int,
    handle: row[ApiParams.handle] as String?,
    mutualCount: row[ApiParams.mutualCount] as int? ?? 0,
  );
}
