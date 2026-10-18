import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../repositories/push_repository.dart';
import 'notification_permission_cubit.dart';

/// "Notifications are off on this phone", with a way to turn them on. Shown
/// on the Notifications screen and in Settings; nothing at all while the OS
/// allows notifications, or before it has been asked.
class NotificationsOffBanner extends StatefulWidget {
  const NotificationsOffBanner({super.key});

  @override
  State<NotificationsOffBanner> createState() => _NotificationsOffBannerState();
}

class _NotificationsOffBannerState extends State<NotificationsOffBanner> {
  late final NotificationPermissionCubit _cubit =
      NotificationPermissionCubit(context.read<PushRepository>())..check();

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Back from the settings page is a resume.
    _lifecycle = AppLifecycleListener(
      onStateChange: (s) {
        if (s == AppLifecycleState.resumed) _cubit.check();
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return BlocBuilder<NotificationPermissionCubit, PushPermission?>(
      bloc: _cubit,
      builder: (context, permission) {
        if (permission == null || permission == PushPermission.granted) {
          return const SizedBox.shrink();
        }
        return Container(
          key: const Key('notifications_off_banner'),
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: scheme.errorContainer.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.notifications_off_outlined,
                    color: scheme.onErrorContainer,
                  ),
                  const SizedBox(width: AppSpacing.sm + 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.notificationsOffTitle,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: scheme.onErrorContainer,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          AppStrings.notificationsOffBody,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onErrorContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('notifications_turn_on'),
                  onPressed: _cubit.turnOn,
                  child: const Text(AppStrings.notificationsTurnOn),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
