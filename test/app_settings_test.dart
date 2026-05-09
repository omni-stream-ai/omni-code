import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/settings/app_settings.dart';

void main() {
  test('autoSpeakReplies defaults to false', () {
    expect(AppSettings.defaults().autoSpeakReplies, isFalse);
  });

  test('missing auto_speak_replies falls back to false', () {
    final settings = AppSettings.fromJson(<String, dynamic>{});
    expect(settings.autoSpeakReplies, isFalse);
  });

  test('notificationMaxChars defaults to 160', () {
    expect(AppSettings.defaults().notificationMaxChars, 160);
  });

  test('missing notification_max_chars falls back to default', () {
    final settings = AppSettings.fromJson(<String, dynamic>{});
    expect(settings.notificationMaxChars, 160);
  });

  test('invalid notification_max_chars falls back to default', () {
    final settings = AppSettings.fromJson(<String, dynamic>{
      'notification_max_chars': 0,
    });
    expect(settings.notificationMaxChars, 160);
  });
}
