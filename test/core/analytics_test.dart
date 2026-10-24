import 'package:birthday_app/core/analytics.dart';
import 'package:birthday_app/core/logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stays a no-op until enabled, so Firebase is never touched', () async {
    expect(Analytics.enabled, isFalse);
    await Analytics.signUp();
    await Analytics.contactsImported(3);
    await Analytics.inviteSent('profile');
    await Analytics.wishPosted(withPhoto: true);
    await Analytics.setUser('u1');
    Log.error('boom', Exception('x'));
  });
}
