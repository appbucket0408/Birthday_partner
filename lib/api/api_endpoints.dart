/// Edge Function names and RPC names. No caller spells these inline.
abstract final class ApiEndpoints {
  static const claimProfile = 'claim_profile';
  static const resolveContacts = 'resolve_contacts';
  static const addCelebrations = 'add_celebrations';
  static const deleteAccount = 'delete_account';

  static const rpcPersonCelebratorCount = 'person_celebrator_count';
  static const rpcMyBirthdayStats = 'my_birthday_stats';
  static const rpcMyCelebrates = 'my_celebrates';
  static const rpcCelebrateBack = 'rpc_celebrate_back';
  static const rpcCelebrate = 'rpc_celebrate';
  static const rpcMemberPreview = 'member_preview';
  static const rpcCreateGift = 'rpc_create_gift';
  static const rpcFeedPage = 'feed_page';
  static const rpcMyNotifications = 'my_notifications';
  static const rpcMyUnseenNotificationCount = 'my_unseen_notification_count';
  static const rpcMarkNotificationsSeen = 'mark_notifications_seen';
  static const rpcReportWish = 'rpc_report_wish';
  static const rpcReportPerson = 'rpc_report_person';
  static const rpcMyBlockedPeople = 'my_blocked_people';
}
