import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../models/product.dart';
import '../../repositories/gift_repository.dart';
import '../../repositories/person_repository.dart';
import 'catalog_cubit.dart';
import 'catalog_state.dart';

/// The catalog screen (spec §7): service area, then the active products in
/// it. Reached from a person page's "Send a cake" action -- or, since
/// '/gift/new/:personId' is a real route, from a deep link with nothing but
/// a person id, which is exactly why [CatalogCubit] loads the person itself
/// rather than trusting one was handed down.
///
/// [GiftRepository] and [PersonRepository] are read off context -- both are
/// registered in `app.dart` -- never constructed here, the same convention
/// `PersonScreen` follows.
class CatalogScreen extends StatelessWidget {
  const CatalogScreen({
    super.key,
    required this.personId,
    DateTime Function()? now,
  }) : _now = now;

  final int personId;
  final DateTime Function()? _now;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => CatalogCubit(
        context.read<GiftRepository>(),
        context.read<PersonRepository>(),
        now: _now,
      )..load(personId),
      child: CatalogView(personId: personId),
    );
  }
}

/// The screen's actual content, split out from [CatalogScreen] (not
/// underscore-private) so a widget test can drive it with a mocked
/// [CatalogCubit] via `BlocProvider.value`, the same reason `PersonView` is
/// split from `PersonScreen`.
class CatalogView extends StatelessWidget {
  const CatalogView({super.key, required this.personId});

  final int personId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CatalogCubit, CatalogState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text(AppStrings.giftCatalogTitle),
            // '/gift/new/:personId' is reached with context.go, which
            // REPLACES the page stack -- Navigator.canPop() is false here,
            // so no back arrow renders without this. Same trap that has now
            // bitten '/import', '/settings' and '/person/:personId'.
            leading: IconButton(
              key: const Key('catalog_back_button'),
              icon: const Icon(Icons.arrow_back),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => context.go('/person/$personId'),
            ),
          ),
          body: switch (state) {
            CatalogLoading() =>
              const Center(child: CircularProgressIndicator()),
            CatalogError() => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(state.message),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: () =>
                          context.read<CatalogCubit>().load(personId),
                      child: const Text(AppStrings.retry),
                    ),
                  ],
                ),
              ),
            CatalogLoaded() => _buildLoaded(context, state),
          },
        );
      },
    );
  }

  Widget _buildLoaded(BuildContext context, CatalogLoaded state) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            0,
          ),
          child: Text(
            state.person.displayName,
            key: const Key('catalog_recipient_name'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (state.areas.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              AppStrings.giftNoAreas,
              textAlign: TextAlign.center,
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Text(AppStrings.giftAreaLabel),
                const SizedBox(width: AppSpacing.sm),
                // A plain DropdownButton, not DropdownButtonFormField: this
                // dropdown is not inside a Form and needs no validation or
                // FormField lifecycle, so the plainer widget is the right
                // one here. (Its value-resync-on-rebuild is proven by
                // test/features/gifting/catalog_screen_test.dart, not by
                // this comment.)
                DropdownButton<int>(
                  key: const Key('gift_area_dropdown'),
                  value: state.selectedAreaId,
                  items: [
                    for (final area in state.areas)
                      DropdownMenuItem(
                        value: area.id,
                        child: Text(area.name),
                      ),
                  ],
                  onChanged: (areaId) {
                    if (areaId != null) {
                      context.read<CatalogCubit>().selectArea(areaId);
                    }
                  },
                ),
              ],
            ),
          ),
        Expanded(
          child: state.products.isEmpty
              ? Center(
                  child: Text(
                    AppStrings.giftNoProducts,
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView(
                  children: [
                    for (final product in state.products)
                      ListTile(
                        key: Key('product_${product.id}'),
                        title: Text(product.name),
                        subtitle: Text(_subtitleFor(product)),
                        // Product.priceLabel already carries the '₹' -- see
                        // its doc. No AppStrings template wraps it.
                        trailing: Text(product.priceLabel),
                        onTap: () => _openSlotPicker(context, state, product),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  String _subtitleFor(Product product) {
    final parts = [
      if (product.flavour != null) product.flavour!,
      if (product.size != null) product.size!,
    ];
    return parts.join(' · ');
  }

  /// Pushes the slot picker, carrying the chosen product forward, per spec
  /// §7 -- Task 6 builds `SlotPickerScreen` itself and is expected to
  /// replace this call with `Navigator.push(context,
  /// MaterialPageRoute(builder: (_) => SlotPickerScreen(personId: ...,
  /// product: product)))`. Left as an explicit placeholder rather than a
  /// silent no-op so the interaction is visibly wired end to end today: this
  /// file is the only one Task 5 is scoped to create or modify, and
  /// task-6-brief.md's own file list does not list catalog_screen.dart as a
  /// file it modifies, even though wiring the real screen in requires
  /// touching this exact call site.
  void _openSlotPicker(
    BuildContext context,
    CatalogLoaded state,
    Product product,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SlotPickerPlaceholder(
          personId: personId,
          product: product,
        ),
      ),
    );
  }
}

/// Stands in for Task 6's `SlotPickerScreen`. Pushed (not routed), the same
/// as the real thing will be, so the default back arrow is supplied by the
/// framework and no `leading` is needed here.
class _SlotPickerPlaceholder extends StatelessWidget {
  const _SlotPickerPlaceholder({required this.personId, required this.product});

  final int personId;
  final Product product;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(product.name)),
      body: Center(
        child: Text('Delivery windows for ${product.name} — coming in a '
            'later task.'),
      ),
    );
  }
}
