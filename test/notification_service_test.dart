import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/services/notification_service.dart';

void main() {
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
