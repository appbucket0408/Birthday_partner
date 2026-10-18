import '../api/api_params.dart';

/// A row in public.wishes, with its author's name resolved separately.
///
/// [authorName] is null when the viewer is not connected to the author.
/// `profiles_select_own` restricts profiles to their owner, so a wall cannot
/// read another author's profile at all; names come from the author's `people`
/// row instead, which RLS filters through private.can_see_person. An author the
/// viewer neither celebrates nor is celebrated by simply does not come back,
/// and the wish renders unattributed. That is the intended privacy outcome, not
/// a gap to work around.
class Wish {
  const Wish({
    required this.id,
    required this.authorProfileId,
    required this.subjectPersonId,
    required this.body,
    required this.occasionYear,
    required this.createdAt,
    this.photoPath,
    this.authorName,
  });

  final int id;
  final String authorProfileId;
  final int subjectPersonId;
  final String body;
  final int occasionYear;
  final DateTime createdAt;

  /// Storage path of the attached photo in the `wish_photos` bucket, or null
  /// for a text-only wish.
  final String? photoPath;
  final String? authorName;

  // Deliberately no `isMine` getter. Authorship is decided by comparing
  // [authorProfileId] to the signed-in user id, which this model does not have
  // and must not guess. The screen reads it from the session.

  Wish withAuthorName(String? name) => Wish(
        id: id,
        authorProfileId: authorProfileId,
        subjectPersonId: subjectPersonId,
        body: body,
        occasionYear: occasionYear,
        createdAt: createdAt,
        photoPath: photoPath,
        authorName: name,
      );

  factory Wish.fromRow(Map<String, dynamic> row) => Wish(
        id: row[ApiParams.id] as int,
        authorProfileId: row[ApiParams.authorProfileId] as String,
        subjectPersonId: row[ApiParams.subjectPersonId] as int,
        body: row[ApiParams.body] as String,
        occasionYear: row[ApiParams.occasionYear] as int,
        createdAt: DateTime.parse(row[ApiParams.createdAt] as String),
        photoPath: row[ApiParams.photoPath] as String?,
      );
}
