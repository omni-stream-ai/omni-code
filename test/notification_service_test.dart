import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/services/notification_service.dart';
import 'package:omni_code/src/settings/app_settings.dart';

void main() {
  test('notification sound mode respects notification importance', () {
    expect(
      shouldPlayNotificationSound(NotificationSoundMode.all, important: false),
      isTrue,
    );
    expect(
      shouldPlayNotificationSound(
        NotificationSoundMode.importantOnly,
        important: false,
      ),
      isFalse,
    );
    expect(
      shouldPlayNotificationSound(
        NotificationSoundMode.importantOnly,
        important: true,
      ),
      isTrue,
    );
    expect(
      shouldPlayNotificationSound(
        NotificationSoundMode.muted,
        important: true,
      ),
      isFalse,
    );
  });

  test('truncateNotificationBody keeps short text unchanged', () {
    expect(truncateNotificationBody('hello', 10), 'hello');
  });

  test('truncateNotificationBody trims and truncates long text', () {
    expect(
      truncateNotificationBody('  1234567890  ', 8),
      '12345...',
    );
  });

  test('truncateNotificationBody handles very small limits', () {
    expect(truncateNotificationBody('123456', 3), '123');
  });
}
