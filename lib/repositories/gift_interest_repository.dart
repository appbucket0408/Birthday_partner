/// "Notify me when cake gifting is live" -- interest recorded while the
/// gifting flow is not available yet (20261017000007_gift_interest.sql).
abstract interface class GiftInterestRepository {
  /// Whether the signed-in user already asked to be told, for [personId].
  Future<bool> isRegistered(int personId);

  /// Records the signed-in user's interest in sending [personId] a cake.
  /// Idempotent: asking twice is the same as asking once.
  Future<void> register(int personId);
}
