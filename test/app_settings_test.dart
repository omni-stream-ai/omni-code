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

  test('bridge local speech providers round-trip through json', () {
    final settings = AppSettings.defaults().copyWith(
      asrProvider: AsrProvider.bridgeLocal,
      ttsProvider: TtsProvider.bridgeLocal,
      bridgeLocalTtsVoice: '2',
      bridgeLocalTtsStreaming: true,
      callModeAllowInterruptions: false,
      callModeSpeechPauseMillis: 1800,
    );

    final restored = AppSettings.fromJson(settings.toJson());

    expect(restored.asrProvider, AsrProvider.bridgeLocal);
    expect(restored.ttsProvider, TtsProvider.bridgeLocal);
    expect(restored.bridgeLocalTtsVoice, '2');
    expect(restored.bridgeLocalTtsStreaming, isTrue);
    expect(restored.callModeAllowInterruptions, isFalse);
    expect(restored.callModeSpeechPauseMillis, 1800);
  });

  test('legacy bridge provider value migrates to bridge local', () {
    final settings = AppSettings.fromJson(<String, dynamic>{
      'asr_provider': 'bridge',
      'tts_provider': 'bridge',
    });

    expect(settings.asrProvider, AsrProvider.bridgeLocal);
    expect(settings.ttsProvider, TtsProvider.bridgeLocal);
  });

  test('removed speech provider values migrate to system', () {
    final settings = AppSettings.fromJson(<String, dynamic>{
      'asr_provider': 'tencentCloudStreaming',
      'tts_provider': 'zhipu',
    });

    expect(settings.asrProvider, AsrProvider.system);
    expect(settings.ttsProvider, TtsProvider.system);
  });

  test('updateTargetVersion defaults to empty string', () {
    expect(AppSettings.defaults().updateTargetVersion, isEmpty);
  });

  test('call mode interruption defaults to true', () {
    expect(AppSettings.defaults().callModeAllowInterruptions, isTrue);
  });

  test('invalid call mode speech pause falls back to default', () {
    final settings = AppSettings.fromJson(<String, dynamic>{
      'call_mode_speech_pause_millis': 100,
    });
    expect(
      settings.callModeSpeechPauseMillis,
      defaultCallModeSpeechPauseMillis,
    );
  });

  test('reads and trims update_target_version', () {
    final settings = AppSettings.fromJson(<String, dynamic>{
      'update_target_version': '  v0.2.1  ',
    });
    expect(settings.updateTargetVersion, 'v0.2.1');
  });
}
