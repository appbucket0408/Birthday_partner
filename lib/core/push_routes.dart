/// Turns an FCM data payload into a route, or null.
///
/// The payload is attacker-influenced in the same way display_name is: a
/// path segment built from unchecked text is how a tapped notification
/// becomes a navigation to somewhere the sender chose. Only a positive
/// integer is accepted, and the route is rebuilt from the parsed int rather
/// than from the original string, so nothing from the payload reaches the
/// router verbatim.
String? routeForPayload(Map<String, dynamic> data) {
  final raw = data['person_id'];
  if (raw is! String) return null;
  final id = int.tryParse(raw);
  if (id == null || id <= 0) return null;
  return '/person/$id';
}
