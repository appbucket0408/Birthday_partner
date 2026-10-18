import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_strings.dart';
import 'notification_badge_cubit.dart';

/// The bell in each tab's app bar, with the unread count, opening the
/// Notifications screen.
///
/// Renders nothing when no [NotificationBadgeCubit] is above it. In the app
/// there always is one (app.dart); the many widget tests that pump a single
/// tab screen on its own have none, and a bell they do not exercise should
/// not make every one of them provide a fake.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  NotificationBadgeCubit? _badge;
  AppLifecycleListener? _lifecycle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_badge != null) return;
    try {
      _badge = context.read<NotificationBadgeCubit>();
    } on ProviderNotFoundException {
      return;
    }
    // Every tab builds a bell at once (they live in an IndexedStack), so
    // these refreshes overlap; the cubit runs one and drops the rest.
    _badge!.refresh();
    _lifecycle = AppLifecycleListener(
      onStateChange: (s) {
        if (s == AppLifecycleState.resumed) _badge?.refresh();
      },
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    await context.push('/notifications');
    _badge?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final badge = _badge;
    if (badge == null) return const SizedBox.shrink();
    return BlocBuilder<NotificationBadgeCubit, int>(
      bloc: badge,
      builder: (context, count) => IconButton(
        key: const Key('notification_bell'),
        tooltip: AppStrings.notificationsBellTooltip,
        onPressed: _open,
        icon: Badge(
          key: const Key('notification_bell_badge'),
          isLabelVisible: count > 0,
          label: Text(count > 99 ? '99+' : '$count'),
          child: Icon(
            count > 0 ? Icons.notifications : Icons.notifications_none,
          ),
        ),
      ),
    );
  }
}
