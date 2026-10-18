import 'dart:convert';


String? routeForPayload(Map<String, dynamic> data) {
  final raw = data['person_id'];
  if (raw is! String) return null;
  final id = int.tryParse(raw);
  if (id == null || id <= 0) return null;
  return '/person/$id';
}

/// The FCM data payload, carried through a local notification.
///
/// A message that arrives while the app is open is re-shown with
/// flutter_local_notifications, whose payload is a single string. Encoding
/// the whole `data` map, rather than picking out a route here, keeps
/// [routeForPayload] the only place a payload becomes a route.
String localPayloadFor(Map<String, dynamic> data) => jsonEncode(data);

/// The route for a tapped local notification's [payload], or null.
///
/// Decodes what [localPayloadFor] wrote and hands it to [routeForPayload],
/// so a tap on a foreground banner validates and routes exactly like a tap
/// on an FCM one. Anything that is not a JSON object routes nowhere: the
/// string came back through the OS and is no more trusted than the payload.
String? routeForLocalPayload(String? payload) {
  if (payload == null) return null;
  try {
    final decoded = jsonDecode(payload);
    return decoded is Map<String, dynamic> ? routeForPayload(decoded) : null;
  } on FormatException {
    return null;
  }
}
