import 'package:flutter_meta_appads_sdk/flutter_meta_appads_sdk.dart';

/// Every analytics event. [toMeta] picks the few that optimise ad delivery.
enum AppEvent {
  signUp(
    'sign_up',
    toMeta: true,
    metaStandard: FBStandardEvent.completedRegistration,
  ),
  contactsPermission('contacts_permission'),
  contactsImported('contacts_imported', toMeta: true),
  inviteSent('invite_sent', toMeta: true),
  wishPosted('wish_posted', toMeta: true),
  feedScrolled('feed_scrolled'),
  celebrateBack('celebrate_back'),
  celebrate('celebrate');

  const AppEvent(this.eventName, {this.toMeta = false, this.metaStandard});

  final String eventName;
  final bool toMeta;

  /// Logged as this Meta standard event instead of a custom one.
  final FBStandardEvent? metaStandard;
}

/// Parameter keys, shared by call sites and providers.
abstract final class AppParam {
  static const method = 'method';
  static const granted = 'granted';
  static const added = 'added';
  static const source = 'source';
  static const withPhoto = 'with_photo';
  static const postsLoaded = 'posts_loaded';
}
