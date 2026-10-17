import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../repositories/gift_interest_repository.dart';
import '../../repositories/person_repository.dart';
import 'cake_coming_soon_cubit.dart';

/// Where "Send a cake" goes until gifting is live: a preview of what is
/// coming, and "Notify me" to register interest -- which both measures
/// demand and gives the user a real next step instead of a dead end.
///
/// The catalog flow (CatalogScreen and on) is kept, unlinked, for when
/// payments exist; '/gift/new/:personId' points here until then.
class CakeComingSoonScreen extends StatelessWidget {
  const CakeComingSoonScreen({super.key, required this.personId});

  final int personId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => CakeComingSoonCubit(
        c.read<PersonRepository>(),
        c.read<GiftInterestRepository>(),
        personId,
      )..load(),
      child: CakeComingSoonView(personId: personId),
    );
  }
}

/// Split out so a widget test can drive it with its own cubit.
class CakeComingSoonView extends StatelessWidget {
  const CakeComingSoonView({super.key, required this.personId});

  final int personId;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CakeComingSoonCubit, CakeComingSoonState>(
      listenWhen: (_, next) => next is CakeComingSoonReady && next.error != null,
      listener: (context, state) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((state as CakeComingSoonReady).error!)),
      ),
      builder: (context, state) {
        final ready = state is CakeComingSoonReady ? state : null;
        return Scaffold(
          appBar: AppBar(
            // Reached with context.go, which replaces the page stack: the
            // way back to the person is explicit.
            leading: IconButton(
              key: const Key('cake_back_button'),
              icon: const Icon(Icons.close),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => context.go('/person/$personId'),
            ),
          ),
          body: ready == null
              ? const Center(child: CircularProgressIndicator())
              : _Body(state: ready),
          bottomNavigationBar:
              ready == null ? null : _NotifyBar(state: ready, personId: personId),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state});

  final CakeComingSoonReady state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primaryContainer, scheme.tertiaryContainer],
              ),
            ),
            alignment: Alignment.center,
            child: const Text('🎂', style: TextStyle(fontSize: 56)),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            key: const Key('cake_coming_soon_badge'),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(AppSpacing.lg),
            ),
            child: Text(
              AppStrings.cakeComingSoonBadge,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            AppStrings.cakeTitleTemplate.replaceFirst('%s', state.name),
            key: const Key('cake_title'),
            textAlign: TextAlign.center,
            style:
                theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            AppStrings.cakeSubtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xl),
          const _Feature(
            emoji: '🍰',
            title: AppStrings.cakeFeatureFreshTitle,
            body: AppStrings.cakeFeatureFreshBody,
          ),
          const _Feature(
            emoji: '🚚',
            title: AppStrings.cakeFeatureDeliveryTitle,
            body: AppStrings.cakeFeatureDeliveryBody,
          ),
          const _Feature(
            emoji: '💌',
            title: AppStrings.cakeFeatureNoteTitle,
            body: AppStrings.cakeFeatureNoteBody,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({
    required this.emoji,
    required this.title,
    required this.body,
  });

  final String emoji;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: scheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: scheme.secondaryContainer,
                child: Text(emoji, style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Notify me" pinned at the bottom; once tapped, a calm confirmation in its
/// place -- the user has done all there is to do here.
class _NotifyBar extends StatelessWidget {
  const _NotifyBar({required this.state, required this.personId});

  final CakeComingSoonReady state;
  final int personId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: state.registered
              ? Column(
                  key: const Key('cake_registered'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(AppSpacing.md),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: scheme.primary),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppStrings.cakeRegisteredTitle,
                                  style: theme.textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  AppStrings.cakeRegisteredBody,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                      key: const Key('cake_done'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                      ),
                      onPressed: () => context.go('/person/$personId'),
                      child: const Text(AppStrings.importDone),
                    ),
                  ],
                )
              : FilledButton.icon(
                  key: const Key('cake_notify_me'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: state.saving
                      ? null
                      : () {
                          HapticFeedback.lightImpact();
                          context.read<CakeComingSoonCubit>().notifyMe();
                        },
                  icon: state.saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.notifications_active_outlined),
                  label: const Text(AppStrings.cakeNotifyMe),
                ),
        ),
      ),
    );
  }
}
