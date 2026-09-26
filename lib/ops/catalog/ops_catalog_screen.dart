import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../models/product.dart';
import '../../repositories/ops_repository.dart';
import 'ops_catalog_cubit.dart';
import 'ops_catalog_state.dart';

/// Service areas and the products in one of them: add a product, and turn
/// one on or off.
class OpsCatalogScreen extends StatelessWidget {
  const OpsCatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => OpsCatalogCubit(context.read<OpsRepository>())
        ..load(),
      child: const OpsCatalogView(),
    );
  }
}

/// Split out so tests can pump it with a cubit they control, without the
/// provider wiring.
class OpsCatalogView extends StatefulWidget {
  const OpsCatalogView({super.key});

  @override
  State<OpsCatalogView> createState() => _OpsCatalogViewState();
}

class _OpsCatalogViewState extends State<OpsCatalogView> {
  final _name = TextEditingController();
  final _flavour = TextEditingController();
  final _size = TextEditingController();
  final _price = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _flavour.dispose();
    _size.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.opsCatalogTab),
        actions: [
          TextButton(
            key: const Key('ops_go_slots'),
            onPressed: () => context.go('/slots'),
            child: const Text(AppStrings.opsSlotsTab),
          ),
        ],
      ),
      body: BlocBuilder<OpsCatalogCubit, OpsCatalogState>(
        builder: (context, state) {
          if (state is OpsCatalogLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is OpsCatalogError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message, key: const Key('ops_catalog_error')),
                  const SizedBox(height: AppSpacing.md),
                  TextButton(
                    onPressed: () => context.read<OpsCatalogCubit>().load(),
                    child: const Text(AppStrings.retry),
                  ),
                ],
              ),
            );
          }

          final loaded = state as OpsCatalogLoaded;
          if (loaded.areas.isEmpty) {
            return const Center(child: Text(AppStrings.opsNoAreas));
          }

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // Assert on this widget's `.value` in tests, never find.text:
              // a DropdownButton keeps every item mounted in an IndexedStack
              // and they are not Offstage-wrapped, so a text assertion
              // passes regardless of which one is selected.
              DropdownButton<int>(
                key: const Key('ops_area_dropdown'),
                value: loaded.selectedAreaId,
                isExpanded: true,
                items: [
                  for (final a in loaded.areas)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (id) {
                  if (id != null) {
                    context.read<OpsCatalogCubit>().selectArea(id);
                  }
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              if (loaded.products.isEmpty)
                const Text(AppStrings.opsNoProducts)
              else
                for (final p in loaded.products) _ProductRow(product: p),
              const Divider(height: AppSpacing.xl),
              _addForm(context),
            ],
          );
        },
      ),
    );
  }

  Widget _addForm(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('ops_new_name'),
            controller: _name,
            decoration:
                const InputDecoration(labelText: AppStrings.opsProductName),
          ),
          TextField(
            key: const Key('ops_new_flavour'),
            controller: _flavour,
            decoration:
                const InputDecoration(labelText: AppStrings.opsProductFlavour),
          ),
          TextField(
            key: const Key('ops_new_size'),
            controller: _size,
            decoration:
                const InputDecoration(labelText: AppStrings.opsProductSize),
          ),
          TextField(
            key: const Key('ops_new_price'),
            controller: _price,
            keyboardType: TextInputType.number,
            decoration:
                const InputDecoration(labelText: AppStrings.opsProductPrice),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            key: const Key('ops_add_product'),
            onPressed: () => context.read<OpsCatalogCubit>().addProduct(
                  name: _name.text,
                  flavour: _flavour.text,
                  size: _size.text,
                  priceText: _price.text,
                ),
            child: const Text(AppStrings.opsAddProduct),
          ),
        ],
      );
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final detail = [product.flavour, product.size]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' · ');

    return ListTile(
      key: Key('ops_product_${product.id}'),
      title: Text(product.name),
      subtitle: Text(
        detail.isEmpty
            ? product.priceLabel
            : '$detail · ${product.priceLabel}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            product.isActive ? AppStrings.opsActive : AppStrings.opsInactive,
          ),
          Switch(
            key: Key('ops_product_toggle_${product.id}'),
            value: product.isActive,
            onChanged: (v) => context
                .read<OpsCatalogCubit>()
                .toggleActive(product.id, isActive: v),
          ),
        ],
      ),
    );
  }
}
