import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/push_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/settings_repository_impl.dart';
import '../../router/session_cubit.dart';
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

/// The whole screen's layout lives on this one class, inline in [build] --
/// same convention as TimelineScreen's `_TimelineView`: nothing here is
/// reused elsewhere or complex enough to earn its own widget.
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
        // exactly as I2 fixed the import screens' exits.
        leading: IconButton(
          key: const Key('settings_back_button'),
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => context.go('/timeline'),
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
    final errorColor = Theme.of(context).colorScheme.error;
    return ListView(
      children: [
        SwitchListTile(
          key: const Key('reminders_switch'),
          title: const Text(AppStrings.settingsReminders),
          subtitle: const Text(AppStrings.settingsRemindersBody),
          value: state.remindersEnabled,
          onChanged: state.savingReminders
              ? null
              : (value) => cubit.toggleReminders(value),
        ),
        const Divider(height: 1),
        ListTile(
          key: const Key('sign_out_tile'),
          title: const Text(AppStrings.settingsSignOut),
          onTap: cubit.signOut,
        ),
        ListTile(
          key: const Key('delete_account_tile'),
          title: Text(
            AppStrings.settingsDeleteAccount,
            style: TextStyle(color: errorColor),
          ),
          iconColor: errorColor,
          onTap: () => _confirmDelete(context, cubit),
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
