import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/app_text_styles.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/push_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/settings_repository_impl.dart';
import '../../router/session_cubit.dart';
import '../push/notifications_off_banner.dart';
import 'settings_cubit.dart';
import 'settings_state.dart';

/// Settings (spec §6.4): the reminders toggle, sign out and account
/// deletion -- the last two irreversible from the user's point of view.
///
/// [repository] is constructor-injected rather than read off context, same
/// reason as [GraphRepository] in TimelineScreen: SettingsRepository has no
/// RepositoryProvider anywhere in this app. AuthRepository DOES have one
/// (set up in app.dart), so it is read from context, matching
/// PhoneScreen/ProfileSetupScreen.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, SettingsRepository? repository})
    : _repository = repository;

  final SettingsRepository? _repository;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => SettingsCubit(
        _repository ?? SettingsRepositoryImpl(ApiClient.instance),
        c.read<AuthRepository>(),
        // Read off context with no `?? ConcreteImpl(...)` fallback, the
        // convention every other repository here follows. The older
        // `_repository` parameter above predates it and is left alone --
        // changing it is not this phase's work.
        c.read<PushRepository>(),
      )..load(),
      child: const _SettingsView(),
    );
  }
}

/// The screen's layout lives on this class, inline in [build] -- same
/// convention as TimelineScreen's `_TimelineView`. Only the purely visual
/// pieces (section label, card group, icon tile) are split out below.
class _SettingsView extends StatelessWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.settingsTitle),
        // '/settings' is a top-level GoRoute, a sibling of '/timeline' --
        // context.go('/settings') replaces the page stack with a single
        // page, so Navigator.canPop() is false and automaticallyImplyLeading
        // finds nothing to pop. Without an explicit leading control this
        // screen was a reachable dead-end: no back arrow, no other
        // navigation anywhere in the settings feature, and on Android
        // hardware back would pop an empty stack and exit the app. Fixed
        // exactly as I2 fixed the import screens' exits. Back goes to the
        // Profile tab, which is where the only settings button lives.
        leading: IconButton(
          key: const Key('settings_back_button'),
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => context.go('/profile'),
        ),
      ),
      body: BlocConsumer<SettingsCubit, SettingsState>(
        listener: (context, state) {
          if (state is SettingsSignedOut) {
            // SettingsCubit has no SessionCubit reference (see its class
            // doc) -- the screen is what notifies it, same shape as
            // PhoneVerified/ProfileSetupDone telling SessionCubit to
            // re-derive routing state. This is what actually moves the app
            // off /settings: the router's redirect switches on
            // SessionState, which nothing else here changes.
            context.read<SessionCubit>().signOut();
            return;
          }
          if (state is SettingsLoaded && state.error != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.error!)));
          }
        },
        builder: (context, state) => switch (state) {
          SettingsLoading() => const Center(child: CircularProgressIndicator()),
          SettingsSignedOut() => const Center(
            child: CircularProgressIndicator(),
          ),
          SettingsLoadError() => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(state.message),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: () => context.read<SettingsCubit>().load(),
                  child: const Text(AppStrings.retry),
                ),
              ],
            ),
          ),
          SettingsLoaded() => _buildLoaded(context, state),
        },
      ),
    );
  }

  Widget _buildLoaded(BuildContext context, SettingsLoaded state) {
    final cubit = context.read<SettingsCubit>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rowTitle =
        theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      children: [
        // The two switches below only choose WHAT to send; if the phone
        // blocks notifications, nothing arrives either way, so say so first.
        const NotificationsOffBanner(),
        const _SectionLabel(AppStrings.settingsSectionNotifications),
        _Group(
          children: [
            SwitchListTile(
              key: const Key('reminders_switch'),
              contentPadding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.xs,
              ),
              secondary: _IconTile(
                icon: Icons.notifications_none_rounded,
                background: scheme.primaryContainer,
                foreground: scheme.onPrimaryContainer,
              ),
              title: Text(AppStrings.settingsReminders, style: rowTitle),
              subtitle: const Text(AppStrings.settingsRemindersBody),
              value: state.remindersEnabled,
              onChanged: state.savingReminders
                  ? null
                  : (value) => cubit.toggleReminders(value),
            ),
            SwitchListTile(
              key: const Key('wish_notifications_switch'),
              contentPadding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.xs,
              ),
              secondary: _IconTile(
                icon: Icons.chat_bubble_outline_rounded,
                background: scheme.secondaryContainer,
                foreground: scheme.onSecondaryContainer,
              ),
              title: Text(AppStrings.settingsWishNotifications, style: rowTitle),
              subtitle: const Text(AppStrings.settingsWishNotificationsBody),
              value: state.wishNotificationsEnabled,
              onChanged: state.savingWishNotifications
                  ? null
                  : (value) => cubit.toggleWishNotifications(value),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const _SectionLabel(AppStrings.settingsSectionAccount),
        _Group(
          children: [
            ListTile(
              key: const Key('blocked_people_tile'),
              leading: _IconTile(
                icon: Icons.block,
                background: scheme.surfaceContainerHigh,
                foreground: scheme.onSurfaceVariant,
              ),
              title: Text(AppStrings.settingsBlocked, style: rowTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/blocked'),
            ),
            ListTile(
              key: const Key('sign_out_tile'),
              leading: _IconTile(
                icon: Icons.logout_rounded,
                background: scheme.surfaceContainerHigh,
                foreground: scheme.onSurfaceVariant,
              ),
              title: Text(AppStrings.settingsSignOut, style: rowTitle),
              onTap: cubit.signOut,
            ),
            ListTile(
              key: const Key('delete_account_tile'),
              leading: _IconTile(
                icon: Icons.delete_outline_rounded,
                background: scheme.error.withValues(alpha: 0.12),
                foreground: scheme.error,
              ),
              title: Text(
                AppStrings.settingsDeleteAccount,
                style: rowTitle?.copyWith(color: scheme.error),
              ),
              onTap: () => _confirmDelete(context, cubit),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, SettingsCubit cubit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.settingsDeleteTitle),
        content: const Text(AppStrings.settingsDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            key: const Key('delete_confirm_button'),
            // Destructive, so it reads as such.
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(AppStrings.settingsDeleteConfirm),
          ),
        ],
      ),
    );
    // The dialog's own Navigator.pop already happened; this await is what
    // creates the async gap Task 8 was bitten by. `context` is not touched
    // again unless it is still mounted.
    if (confirmed != true || !context.mounted) return;
    cubit.deleteAccount();
  }
}

/// A small heading above a group of rows.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(
          left: AppSpacing.xs,
          top: AppSpacing.sm,
          bottom: AppSpacing.sm,
        ),
        child: Text(text, style: AppTextStyles.sectionHeader(context)),
      );
}

/// Rows on one white card, hairline dividers between them -- the same
/// grouping as the Dashboard's sections.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 68,
                color: scheme.outlineVariant.withValues(alpha: 0.7),
              ),
            child,
          ],
        ],
      ),
    );
  }
}

/// A row's icon on a soft rounded square.
class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(icon, size: 20, color: foreground),
      );
}
