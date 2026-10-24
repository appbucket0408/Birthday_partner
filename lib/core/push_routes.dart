import 'dart:convert';

// Only these tab routes may come from a payload.
const _screens = {
  'celebrates': '/profile/celebrates',
  'dashboard': '/timeline',
};

String? routeForPayload(Map<String, dynamic> data) {
  if (_screens[data['screen']] case final route?) return route;
  final id = _positiveId(data['person_id']);
  if (id == null) return null;
  final wishId = _positiveId(data['wish_id']);
  return wishId == null ? '/person/$id' : '/person/$id?wish=$wishId';
}

/// FCM data values are always strings; anything else is not ours.
int? _positiveId(Object? raw) {
  if (raw is! String) return null;
  final id = int.tryParse(raw);
  return id == null || id <= 0 ? null : id;
}

String localPayloadFor(Map<String, dynamic> data) => jsonEncode(data);

String? routeForLocalPayload(String? payload) {
  if (payload == null) return null;
  try {
    final decoded = jsonDecode(payload);
    return decoded is Map<String, dynamic> ? routeForPayload(decoded) : null;
  } on FormatException {
    return null;
  }
}
