import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/app_text_styles.dart';
import '../../core/initial_avatar.dart';
import '../../repositories/contacts_repository.dart';
import 'import_cubit.dart';
import 'import_state.dart';
import 'import_summary_screen.dart';

class ImportPickScreen extends StatefulWidget {
  const ImportPickScreen({super.key});

  @override
  State<ImportPickScreen> createState() => _ImportPickScreenState();
}

class _ImportPickScreenState extends State<ImportPickScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ImportCubit, ImportState>(
      listenWhen: (prev, next) => prev is! ImportDone && next is ImportDone,
      listener: (context, state) {
        // Only the route on top pushes the summary (same guard as
        // PhoneScreen / OtpScreen, Task 7), so a commit() retried from the
        // summary screen does not push a second one from here.
        final isCurrent = ModalRoute.of(context)?.isCurrent ?? false;
        if (state is ImportDone && isCurrent) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BlocProvider.value(
                value: context.read<ImportCubit>(),
                child: const ImportSummaryScreen(),
              ),
            ),
          );
        }
      },
      builder: (context, state) {
        final picking = state is ImportPicking ? state : null;
        return Scaffold(
          appBar: AppBar(title: const Text(AppStrings.importPickTitle)),
          body: switch (state) {
            ImportCommitting() => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: AppSpacing.md),
                    Text('${state.done}/${state.total}'),
                  ],
                ),
              ),
            ImportFailed() => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(AppStrings.somethingWentWrong),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: () => context.read<ImportCubit>().commit(),
                      child: const Text(AppStrings.retry),
                    ),
                  ],
                ),
              ),
            ImportPicking() => _PickList(picking: state, search: _search),
            _ => const Center(child: CircularProgressIndicator()),
          },
          // Pinned and inside the safe area: it used to sit under Android's
          // navigation bar, half-hidden and hard to tap.
          bottomNavigationBar: picking == null
              ? null
              : _AddBar(count: picking.selected.length),
        );
      },
    );
  }
}

class _PickList extends StatelessWidget {
  const _PickList({required this.picking, required this.search});

  final ImportPicking picking;
  final TextEditingController search;

  @override
  Widget build(BuildContext context) {
    if (picking.contacts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Text(AppStrings.importNoContacts, textAlign: TextAlign.center),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: TextField(
            key: const Key('import_search'),
            controller: search,
            decoration: InputDecoration(
              hintText: AppStrings.connectionsSearch,
              prefixIcon: const Icon(Icons.search),
              filled: true,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.md),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: search,
            builder: (context, query, _) => _sections(context, query.text),
          ),
        ),
      ],
    );
  }

  Widget _sections(BuildContext context, String query) {
    final q = query.trim().toLowerCase();
    int byName(DeviceContact a, DeviceContact b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    final shown = [
      for (final c in picking.contacts)
        if (q.isEmpty ||
            c.name.toLowerCase().contains(q) ||
            c.phoneE164.contains(q))
          c,
    ];
    // Split by membership: only members have a birthday (only a person sets
    // their own), so the two halves get different promises -- said here, at
    // the moment of choosing, rather than discovered on an empty Calendar.
    final onApp = [
      for (final c in shown)
        if (picking.isMember(c.phoneE164)) c,
    ]..sort(byName);
    final notOnApp = [
      for (final c in shown)
        if (!picking.isMember(c.phoneE164)) c,
    ]..sort(byName);

    if (shown.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(
          AppStrings.connectionsNoMatchesTemplate
              .replaceFirst('%s', query.trim()),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      children: [
        if (onApp.isNotEmpty) ...[
          _SectionHeader(
            key: const Key('import_section_on_app'),
            selectAllKey: const Key('import_select_all_on_app'),
            title: AppStrings.importOnApp,
            hint: AppStrings.importOnAppHint,
            picking: picking,
            contacts: onApp,
          ),
          for (final c in onApp) _ContactRow(contact: c, picking: picking),
        ],
        if (notOnApp.isNotEmpty) ...[
          _SectionHeader(
            key: const Key('import_section_not_on_app'),
            selectAllKey: const Key('import_select_all_not_on_app'),
            title: AppStrings.importNotOnApp,
            hint: AppStrings.importNotOnAppHint,
            picking: picking,
            contacts: notOnApp,
          ),
          for (final c in notOnApp) _ContactRow(contact: c, picking: picking),
        ],
      ],
    );
  }
}

/// A section title and its promise, with "Select all" / "Clear" for the
/// contacts in it that can still be added.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    super.key,
    required this.selectAllKey,
    required this.title,
    required this.hint,
    required this.picking,
    required this.contacts,
  });

  final Key selectAllKey;
  final String title;
  final String hint;
  final ImportPicking picking;
  final List<DeviceContact> contacts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final addable = [
      for (final c in contacts)
        if (!picking.isCelebrating(c.phoneE164)) c.phoneE164,
    ];
    final allSelected =
        addable.isNotEmpty && addable.every(picking.selected.contains);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.sectionHeader(context)),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (addable.isNotEmpty)
            TextButton(
              key: selectAllKey,
              onPressed: () => context
                  .read<ImportCubit>()
                  .setSelected(addable, selected: !allSelected),
              child: Text(
                allSelected ? AppStrings.importClearAll : AppStrings.importSelectAll,
              ),
            ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact, required this.picking});

  final DeviceContact contact;
  final ImportPicking picking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final already = picking.isCelebrating(contact.phoneE164);
    final selected = picking.selected.contains(contact.phoneE164);

    return ListTile(
      key: Key('contact_${contact.phoneE164}'),
      onTap: already
          ? null
          : () => context.read<ImportCubit>().toggle(contact.phoneE164),
      leading: InitialAvatar(name: contact.name, radius: 22),
      title: Text(
        contact.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        _readable(contact.phoneE164),
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      // Someone already celebrated is shown, not offered again.
      trailing: already
          ? Row(
              key: Key('already_${contact.phoneE164}'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  AppStrings.celebratingAlready,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ],
            )
          : Checkbox(
              value: selected,
              shape: const CircleBorder(),
              onChanged: (_) =>
                  context.read<ImportCubit>().toggle(contact.phoneE164),
            ),
    );
  }

  /// "+91 97834 75606" rather than "+919783475606". Falls back to the raw
  /// number for anything the parser cannot format.
  static String _readable(String e164) {
    try {
      final p = PhoneNumber.parse(e164);
      return '+${p.countryCode} ${p.formatNsn()}';
    } catch (_) {
      return e164;
    }
  }
}

/// The commit button, pinned above the system navigation bar, saying what
/// it will do: "Add 3 people", or -- with nothing picked -- what to do first.
class _AddBar extends StatelessWidget {
  const _AddBar({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = switch (count) {
      0 => AppStrings.importSelectPrompt,
      1 => AppStrings.importAddOne,
      _ => AppStrings.importAddManyTemplate.replaceFirst('%s', '$count'),
    };
    return Material(
      elevation: 3,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: FilledButton(
            key: const Key('add_selected'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed:
                count == 0 ? null : () => context.read<ImportCubit>().commit(),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}
