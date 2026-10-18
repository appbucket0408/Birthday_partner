import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_spacing.dart';
import '../../core/app_strings.dart';
import '../../core/photo_picker.dart';
import '../../core/profile_avatar.dart';
import '../../models/profile.dart';
import '../../router/session_cubit.dart';
import '../../router/session_state.dart';
import 'person_cubit.dart';
import 'person_state.dart';

/// Matches the wishes_body_length check in the database.
const _maxWishLength = 250;

/// Matches the wish_photos bucket's file_size_limit.
const _maxPhotoBytes = 5 * 1024 * 1024;

Future<void> openWishComposer(BuildContext context) {
  final cubit = context.read<PersonCubit>();
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => BlocProvider<PersonCubit>.value(
        value: cubit,
        child: const WishComposeScreen(),
      ),
    ),
  );
}

/// Write a wish: the message, and optionally one photo from the gallery.
/// Everything typed and picked stays on screen until the wish is really
/// posted, so a failure can be retried without starting over.
class WishComposeScreen extends StatefulWidget {
  const WishComposeScreen({super.key});

  @override
  State<WishComposeScreen> createState() => _WishComposeScreenState();
}

class _WishComposeScreenState extends State<WishComposeScreen> {
  final _controller = TextEditingController();
  PhotoPicked? _photo;
  String? _error;
  String? _photoError;
  bool _picking = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _photoError = null;
    });
    String? error;
    PhotoPicked? picked;
    try {
      final choice = await pickWishPhoto();
      switch (choice) {
        case null || PhotoRemoved():
          break;
        case PhotoUnsupported():
          error = AppStrings.photoUnsupported;
        case PhotoPicked(:final bytes):
          if (bytes.lengthInBytes > _maxPhotoBytes) {
            error = AppStrings.wishPhotoTooLarge;
          } else if (!await _decodes(bytes)) {
            error = AppStrings.wishPhotoUnreadable;
          } else {
            picked = choice;
          }
      }
    } on PlatformException {
      error = AppStrings.wishPhotoAccessDenied;
    }
    if (!mounted) return;
    setState(() {
      _picking = false;
      _photoError = error;
      if (picked != null) _photo = picked;
    });
  }

  /// A file with an image extension can still be corrupt. Decoding a tiny
  /// thumbnail catches that before it is shown or uploaded.
  static Future<bool> _decodes(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 32);
      codec.dispose();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _removePhoto() => setState(() {
        _photo = null;
        _photoError = null;
      });

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = AppStrings.wishEmpty);
      return;
    }
    // Postgres length() counts code points, so a multi-part emoji counts as
    // several -- the same here.
    if (text.runes.length > _maxWishLength) {
      setState(() => _error = AppStrings.wishTooLong);
      return;
    }
    setState(() {
      _error = null;
      _photoError = null;
    });

    final cubit = context.read<PersonCubit>();
    final messenger = ScaffoldMessenger.of(context);
    await cubit.postWish(text, photo: _photo);
    if (!mounted) return;

    final result = cubit.state;
    if (result is PersonLoaded && result.postError != null) {
      setState(() {
        switch (result.postError) {
          case AppStrings.wishPhotoUploadFailed:
            _photoError = AppStrings.wishPhotoUploadFailed;
          case AppStrings.wishAlreadyThisYear:
            _error = AppStrings.wishAlreadyThisYear;
          default:
            _error = AppStrings.wishPostFailed;
        }
      });
      return;
    }
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(content: Text(AppStrings.wishPosted)),
    );
  }

  void _useSuggestion(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    if (_error != null) setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final me = context.select<SessionCubit, Profile?>(
      (cubit) => switch (cubit.state) {
        SessionReady(:final profile) => profile,
        _ => null,
      },
    );
    return BlocBuilder<PersonCubit, PersonState>(
      builder: (context, state) {
        final posting = state is PersonLoaded && state.posting;
        final name = state is PersonLoaded ? state.person.displayName : '';
        final busy = posting || _picking;
        return PopScope(
          canPop: !posting,
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                key: const Key('wish_close'),
                icon: const Icon(Icons.close),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: posting ? null : () => Navigator.of(context).pop(),
              ),
              title: const Text(AppStrings.wishComposerTitle),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: FilledButton(
                    key: const Key('wish_post'),
                    // Compact in the app bar; the theme's 48dp suits body
                    // buttons, not a toolbar action.
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md + 2,
                      ),
                    ),
                    onPressed: busy ? null : _submit,
                    child: posting
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(AppStrings.wishPost),
                  ),
                ),
              ],
              bottom: posting
                  ? const PreferredSize(
                      preferredSize: Size.fromHeight(2),
                      child: LinearProgressIndicator(minHeight: 2),
                    )
                  : null,
            ),
            body: SafeArea(
              top: false,
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.lg,
                ),
                children: [
                  Row(
                    children: [
                      ProfileAvatar(
                        name: me?.displayName ?? '',
                        path: me?.avatarPath,
                        radius: 22,
                      ),
                      const SizedBox(width: AppSpacing.sm + 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              me?.displayName ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              AppStrings.wishComposerForTemplate.replaceFirst(
                                '%s',
                                name,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    key: const Key('wish_body_field'),
                    controller: _controller,
                    maxLength: _maxWishLength,
                    minLines: 3,
                    maxLines: 8,
                    enabled: !posting,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    decoration: InputDecoration(
                      hintText: AppStrings.wishHint,
                      errorText: _error,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.md),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final suggestion in AppStrings.wishSuggestions)
                          Padding(
                            padding: const EdgeInsets.only(
                              right: AppSpacing.sm,
                            ),
                            child: ActionChip(
                              label: Text(suggestion),
                              onPressed: posting
                                  ? null
                                  : () => _useSuggestion(suggestion),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _PhotoArea(
                    photo: _photo,
                    picking: _picking,
                    enabled: !busy,
                    onPick: _pickPhoto,
                    onRemove: _removePhoto,
                  ),
                  if (_photoError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        _photoError!,
                        key: const Key('wish_photo_error'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    posting
                        ? AppStrings.wishPosting
                        : AppStrings.wishSheetSubtitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The one photo: a tap-to-add tile when there is none, otherwise the photo
/// at its own proportions with Replace and Remove over it.
class _PhotoArea extends StatelessWidget {
  const _PhotoArea({
    required this.photo,
    required this.picking,
    required this.enabled,
    required this.onPick,
    required this.onRemove,
  });

  final PhotoPicked? photo;
  final bool picking;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(AppSpacing.md);
    final photo = this.photo;

    if (photo == null) {
      return Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: radius,
        child: InkWell(
          key: const Key('wish_add_photo'),
          borderRadius: radius,
          onTap: enabled ? onPick : null,
          child: SizedBox(
            height: 160,
            child: Center(
              child: picking
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 36,
                          color: scheme.primary,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          AppStrings.wishAddPhoto,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          AppStrings.wishAddPhotoHint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      );
    }

    final media = MediaQuery.of(context);
    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: media.size.height * 0.5),
            child: Container(
              width: double.infinity,
              color: scheme.surfaceContainerHighest,
              child: Image.memory(
                photo.bytes,
                key: const Key('wish_photo_preview'),
                fit: BoxFit.contain,
                // Decoded at display size, not the upload's full size.
                cacheWidth: (media.size.width * media.devicePixelRatio).round(),
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => SizedBox(
                  height: 160,
                  child: Center(
                    child: Text(
                      AppStrings.wishPhotoUnreadable,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: AppSpacing.sm,
            right: AppSpacing.sm,
            child: IconButton.filledTonal(
              key: const Key('wish_remove_photo'),
              tooltip: AppStrings.wishRemovePhoto,
              icon: const Icon(Icons.close),
              onPressed: enabled ? onRemove : null,
            ),
          ),
          Positioned(
            right: AppSpacing.sm,
            bottom: AppSpacing.sm,
            child: FilledButton.tonalIcon(
              key: const Key('wish_replace_photo'),
              onPressed: enabled ? onPick : null,
              icon: picking
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.photo_library_outlined, size: 18),
              label: const Text(AppStrings.wishReplacePhoto),
            ),
          ),
        ],
      ),
    );
  }
}
