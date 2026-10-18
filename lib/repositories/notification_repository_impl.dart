import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_endpoints.dart';
import '../api/api_error_mapper.dart';
import '../api/api_params.dart';
import '../models/app_notification.dart';
import 'notification_repository.dart';

class NotificationRepositoryImpl implements NotificationRepository {
  const NotificationRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  Future<List<AppNotification>> list({DateTime? before, int limit = 50}) async {
    try {
      final rows = await _client.rpc(
        ApiEndpoints.rpcMyNotifications,
        params: {
          ApiParams.pBefore: before?.toUtc().toIso8601String(),
          ApiParams.pLimit: limit,
        },
      );
      return [
        for (final r in rows as List)
          AppNotification.fromRow(r as Map<String, dynamic>),
      ];
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<int> unseenCount() async {
    try {
      return await _client.rpc(ApiEndpoints.rpcMyUnseenNotificationCount)
          as int;
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> markAllSeen() async {
    try {
      await _client.rpc(ApiEndpoints.rpcMarkNotificationsSeen);
    } catch (e) {
      throw mapError(e);
    }
  }
}
